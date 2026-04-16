require 'base64'
require 'json'
require 'net/http'
require 'openssl'

module Ai
  module Payments
    class PaytrService
      GET_TOKEN_ENDPOINT = 'https://www.paytr.com/odeme/api/get-token'.freeze
      CHECKOUT_ENDPOINT = 'https://www.paytr.com/odeme/'.freeze

      class Error < StandardError; end
      class ConfigurationError < Error; end
      class InvalidAmountError < Error; end
      class InvalidSignatureError < Error; end
      class InvalidPayloadError < Error; end

      ALLOWED_CALLBACK_STATUSES = %w[success failed].freeze

      def create_checkout!(account:, user:, amount_cents:, user_ip:, note: nil)
        raise InvalidAmountError, 'amount_cents must be a positive integer' unless amount_cents.to_i.positive?

        minimum_cents = (minimum_topup_usd * 100).to_i
        raise InvalidAmountError, "minimum topup is #{minimum_topup_usd} USD" if amount_cents < minimum_cents

        validate_configuration!

        merchant_oid = generate_merchant_oid(account.id)
        vat_rate = payments_vat_rate
        paytr_currency = 'USD'
        fx_rate = 1.0

        usd_amount = amount_cents.to_f / 100.0
        gross_usd_amount = usd_amount * (1.0 + vat_rate)
        payment_amount_cents = (gross_usd_amount * 100).round
        payment_amount = payment_amount_cents.to_s

        basket = Base64.strict_encode64([['AI Wallet Topup', format('%.2f', gross_usd_amount), 1]].to_json)
        token = generate_token(
          merchant_oid: merchant_oid,
          user_ip: sanitized_user_ip(user_ip),
          email: user.email.to_s,
          payment_amount: payment_amount,
          user_basket: basket,
          currency: paytr_currency
        )

        payload = {
          merchant_id: merchant_id,
          user_ip: sanitized_user_ip(user_ip),
          merchant_oid: merchant_oid,
          email: user.email.to_s,
          payment_amount: payment_amount,
          paytr_token: token,
          user_basket: basket,
          no_installment: '0',
          max_installment: '0',
          currency: paytr_currency,
          test_mode: paytr_test_mode,
          merchant_ok_url: paytr_ok_url,
          merchant_fail_url: paytr_fail_url,
          timeout_limit: '30'
        }

        response_payload = create_paytr_token(payload)
        paytr_token = response_payload['token'].to_s
        raise Error, 'PayTR token is missing in response' if paytr_token.blank?

        order = AiPaymentOrder.create!(
          account: account,
          user: user,
          provider: 'paytr',
          merchant_oid: merchant_oid,
          status: :pending,
          amount_cents: amount_cents,
          currency: 'USD',
          payment_amount_cents: payment_amount_cents,
          payment_currency: paytr_currency,
          vat_rate: vat_rate,
          fx_rate: fx_rate,
          raw_request: {
            merchant_oid: merchant_oid,
            amount_cents: amount_cents,
            payment_amount_cents: payment_amount_cents,
            payment_currency: paytr_currency,
            test_mode: paytr_test_mode
          },
          meta: {
            note: note,
            checkout_user_id: user.id
          }.compact
        )

        {
          checkout_url: "#{CHECKOUT_ENDPOINT}#{paytr_token}",
          merchant_oid: merchant_oid,
          payment_order_id: order.id
        }
      end

      def process_callback!(payload:)
        merchant_oid = payload[:merchant_oid].to_s
        status = payload[:status].to_s
        total_amount = payload[:total_amount].to_s
        incoming_hash = payload[:hash].to_s

        validate_configuration!
        validate_callback_payload!(
          merchant_oid: merchant_oid,
          status: status,
          total_amount: total_amount,
          incoming_hash: incoming_hash
        )
        verify_callback_hash!(
          merchant_oid: merchant_oid,
          status: status,
          total_amount: total_amount,
          incoming_hash: incoming_hash
        )

        order = AiPaymentOrder.find_by(merchant_oid: merchant_oid)
        return { acknowledged: true, result: 'order_not_found', merchant_oid: merchant_oid } unless order

        result = nil
        order.with_lock do
          unless order.pending?
            result = { acknowledged: true, result: 'already_processed', merchant_oid: merchant_oid, status: order.status }
            next
          end

          callback_snapshot = callback_payload_snapshot(payload)

          if status == 'success'
            validation_error = validate_success_callback_payload(order: order, payload: payload)
            if validation_error.present?
              order.update!(
                status: :failed,
                paytr_status: status,
                fail_reason_code: 'validation_error',
                fail_reason_message: validation_error,
                raw_callback: callback_snapshot,
                failed_at: Time.current
              )

              result = {
                acknowledged: true,
                result: 'failed_validation',
                merchant_oid: merchant_oid,
                validation_error: validation_error
              }
              next
            end

            wallet = AiWallet.find_or_create_by!(account_id: order.account_id) do |ai_wallet|
              ai_wallet.balance_cents = 0
              ai_wallet.currency = 'USD'
              ai_wallet.status = :active
            end

            transaction = nil
            ActiveRecord::Base.transaction do
              order.update!(
                status: :paid,
                paytr_status: status,
                provider_ref: merchant_oid,
                raw_callback: callback_snapshot,
                paid_at: Time.current
              )

              wallet.with_lock do
                wallet.balance_cents += order.payment_amount_cents
                wallet.save!
              end

              transaction = AiTransaction.find_or_create_by!(
                account_id: order.account_id,
                provider: 'paytr',
                provider_ref: merchant_oid
              ) do |ai_transaction|
                ai_transaction.kind = :topup
                ai_transaction.amount_cents = order.payment_amount_cents
                ai_transaction.currency = order.currency
                ai_transaction.meta = {
                  payment_order_id: order.id,
                  paytr_total_amount: total_amount
                }
              end
            end

            result = {
              acknowledged: true,
              result: 'paid',
              merchant_oid: merchant_oid,
              wallet_balance_cents: wallet.reload.balance_cents,
              transaction_id: transaction.id
            }
            next
          end

          order.update!(
            status: :failed,
            paytr_status: status,
            fail_reason_code: payload[:failed_reason_code].to_s.presence,
            fail_reason_message: payload[:failed_reason_msg].to_s.presence,
            raw_callback: callback_snapshot,
            failed_at: Time.current
          )

          result = {
            acknowledged: true,
            result: 'failed',
            merchant_oid: merchant_oid
          }
        end

        result || { acknowledged: true, result: 'failed', merchant_oid: merchant_oid }
      end

      private

      def merchant_id
        ENV['PAYTR_MERCHANT_ID'].to_s
      end

      def merchant_key
        ENV['PAYTR_MERCHANT_KEY'].to_s
      end

      def merchant_salt
        ENV['PAYTR_MERCHANT_SALT'].to_s
      end

      def paytr_ok_url
        ENV['PAYTR_OK_URL'].to_s
      end

      def paytr_fail_url
        ENV['PAYTR_FAIL_URL'].to_s
      end

      def paytr_test_mode
        ENV['PAYTR_TEST_MODE'].to_s == '1' ? '1' : '0'
      end

      def minimum_topup_usd
        value = ENV['MINIMUM_TOPUP_USD'].to_s
        parsed = BigDecimal(value.presence || '10')
        parsed.positive? ? parsed : BigDecimal('10')
      rescue ArgumentError
        BigDecimal('10')
      end

      def payments_vat_rate
        BigDecimal(ENV['PAYMENTS_VAT_RATE'].to_s.presence || '0').to_f
      rescue ArgumentError
        0.0
      end

      def generate_merchant_oid(account_id)
        raw = "AI#{account_id}#{Time.current.to_i}#{SecureRandom.alphanumeric(10)}".upcase.gsub(/[^A-Z0-9]/, '')
        raw.first(32)
      end

      def sanitized_user_ip(raw_ip)
        value = raw_ip.to_s
        return '127.0.0.1' if value.blank?

        value
      end

      def generate_token(merchant_oid:, user_ip:, email:, payment_amount:, user_basket:, currency:)
        data = [
          merchant_id,
          user_ip,
          merchant_oid,
          email,
          payment_amount,
          user_basket,
          '0', # no_installment
          '0', # max_installment
          currency,
          paytr_test_mode
        ].join

        Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', merchant_key, "#{data}#{merchant_salt}"))
      end

      def verify_callback_hash!(merchant_oid:, status:, total_amount:, incoming_hash:)
        token_input = "#{merchant_oid}#{merchant_salt}#{status}#{total_amount}"
        expected = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', merchant_key, token_input))
        hash_matches = incoming_hash.bytesize == expected.bytesize &&
                       ActiveSupport::SecurityUtils.secure_compare(expected, incoming_hash)
        raise InvalidSignatureError, 'invalid callback signature' unless hash_matches
      end

      def create_paytr_token(payload)
        uri = URI.parse(GET_TOKEN_ENDPOINT)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/x-www-form-urlencoded'
        request.body = URI.encode_www_form(payload)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15, open_timeout: 10) do |http|
          http.request(request)
        end

        parsed = JSON.parse(response.body)
        unless response.is_a?(Net::HTTPSuccess) && parsed['status'] == 'success'
          reason = parsed['reason'].presence || response.message
          raise Error, "PayTR token request failed: #{reason}"
        end

        parsed
      rescue JSON::ParserError => e
        raise Error, "PayTR token response parse failed: #{e.message}"
      end

      def validate_configuration!
        missing = []
        missing << 'PAYTR_MERCHANT_ID' if merchant_id.blank?
        missing << 'PAYTR_MERCHANT_KEY' if merchant_key.blank?
        missing << 'PAYTR_MERCHANT_SALT' if merchant_salt.blank?
        missing << 'PAYTR_OK_URL' if paytr_ok_url.blank?
        missing << 'PAYTR_FAIL_URL' if paytr_fail_url.blank?
        raise ConfigurationError, "Missing PayTR config: #{missing.join(', ')}" if missing.any?
      end

      def validate_callback_payload!(merchant_oid:, status:, total_amount:, incoming_hash:)
        raise InvalidPayloadError, 'merchant_oid is missing' if merchant_oid.blank?
        raise InvalidPayloadError, 'merchant_oid format is invalid' unless merchant_oid.match?(/\A[A-Z0-9_-]{1,64}\z/i)
        raise InvalidPayloadError, 'status is invalid' unless ALLOWED_CALLBACK_STATUSES.include?(status)
        raise InvalidPayloadError, 'total_amount is invalid' unless parse_positive_integer(total_amount)
        raise InvalidPayloadError, 'hash is missing' if incoming_hash.blank?
      end

      def callback_payload_snapshot(payload)
        {
          merchant_oid: payload[:merchant_oid].to_s,
          status: payload[:status].to_s,
          total_amount: payload[:total_amount].to_s,
          payment_amount: payload[:payment_amount].to_s.presence,
          currency: payload[:currency].to_s.presence,
          payment_type: payload[:payment_type].to_s.presence,
          test_mode: payload[:test_mode].to_s.presence,
          failed_reason_code: payload[:failed_reason_code].to_s.presence,
          failed_reason_msg: payload[:failed_reason_msg].to_s.presence
        }.compact
      end

      def validate_success_callback_payload(order:, payload:)
        callback_total_amount_cents = parse_positive_integer(payload[:total_amount])
        return 'invalid_total_amount' unless callback_total_amount_cents

        callback_payment_amount_cents = parse_positive_integer(payload[:payment_amount]) if payload[:payment_amount].present?
        callback_currency = payload[:currency].to_s.upcase.presence

        return 'currency_mismatch' if callback_currency.present? && callback_currency != order.payment_currency.to_s.upcase
        return 'payment_amount_mismatch' if callback_payment_amount_cents.present? && callback_payment_amount_cents != order.payment_amount_cents
        return 'total_amount_below_expected' if callback_total_amount_cents < order.payment_amount_cents

        nil
      end

      def parse_positive_integer(value)
        parsed = Integer(value)
        return nil unless parsed.positive?

        parsed
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
