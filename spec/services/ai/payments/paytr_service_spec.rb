require 'rails_helper'

RSpec.describe Ai::Payments::PaytrService do
  let(:service) { described_class.new }
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let!(:wallet) do
    AiWallet.find_or_create_by!(account_id: account.id) do |w|
      w.currency = 'USD'
      w.status = :active
    end.tap do |w|
      w.update!(balance_cents: 1000)
    end
  end

  around do |example|
    with_modified_env(
      'PAYTR_MERCHANT_ID' => 'merchant-id',
      'PAYTR_MERCHANT_KEY' => 'merchant-key',
      'PAYTR_MERCHANT_SALT' => 'merchant-salt',
      'PAYTR_OK_URL' => 'https://example.com/ok',
      'PAYTR_FAIL_URL' => 'https://example.com/fail'
    ) do
      example.run
    end
  end

  def callback_hash(merchant_oid:, status:, total_amount:)
    token_input = "#{merchant_oid}#{ENV.fetch('PAYTR_MERCHANT_SALT')}#{status}#{total_amount}"
    Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', ENV.fetch('PAYTR_MERCHANT_KEY'), token_input))
  end

  describe '#create_checkout!' do
    before do
      stub_request(:post, 'https://www.paytr.com/odeme/api/get-token')
        .to_return(
          status: 200,
          body: { status: 'success', token: 'test-token' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'creates pending order and returns checkout url in USD' do
      result = service.create_checkout!(
        account: account,
        user: user,
        amount_cents: 1500,
        user_ip: '10.1.2.3',
        note: 'spec checkout'
      )

      expect(result[:checkout_url]).to eq('https://www.paytr.com/odeme/test-token')
      expect(result[:merchant_oid]).to be_present
      order = AiPaymentOrder.find(result[:payment_order_id])
      expect(order).to be_pending
      expect(order.payment_currency).to eq('USD')
      expect(order.payment_amount_cents).to eq(1800)
      expect(order.raw_request['payment_currency']).to eq('USD')
      expect(order.meta['note']).to eq('spec checkout')

      expect(a_request(:post, 'https://www.paytr.com/odeme/api/get-token')
        .with { |request| request.body.include?('currency=USD') }).to have_been_made
      expect(a_request(:post, 'https://www.paytr.com/odeme/api/get-token')
        .with { |request| request.body.include?('payment_amount=1800') }).to have_been_made
    end

    it 'uses loopback ip when incoming ip is blank' do
      service.create_checkout!(
        account: account,
        user: user,
        amount_cents: 1500,
        user_ip: ''
      )

      expect(a_request(:post, 'https://www.paytr.com/odeme/api/get-token')
        .with { |request| request.body.include?('user_ip=127.0.0.1') }).to have_been_made
    end

    it 'raises invalid amount for non-positive values' do
      expect do
        service.create_checkout!(account: account, user: user, amount_cents: 0, user_ip: '1.1.1.1')
      end.to raise_error(Ai::Payments::PaytrService::InvalidAmountError)
    end

    it 'raises invalid amount for values below minimum' do
      expect do
        service.create_checkout!(account: account, user: user, amount_cents: 999, user_ip: '1.1.1.1')
      end.to raise_error(Ai::Payments::PaytrService::InvalidAmountError)
    end

    it 'raises configuration error when required env is missing' do
      with_modified_env('PAYTR_MERCHANT_ID' => '') do
        expect do
          service.create_checkout!(account: account, user: user, amount_cents: 1500, user_ip: '1.1.1.1')
        end.to raise_error(Ai::Payments::PaytrService::ConfigurationError)
      end
    end

    it 'raises provider error when paytr returns failed status' do
      stub_request(:post, 'https://www.paytr.com/odeme/api/get-token')
        .to_return(
          status: 200,
          body: { status: 'failed', reason: 'invalid merchant' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect do
        service.create_checkout!(account: account, user: user, amount_cents: 1500, user_ip: '1.1.1.1')
      end.to raise_error(Ai::Payments::PaytrService::Error, /invalid merchant/)
    end

    it 'raises parse error when paytr body is invalid json' do
      stub_request(:post, 'https://www.paytr.com/odeme/api/get-token')
        .to_return(status: 200, body: 'NOT_JSON')

      expect do
        service.create_checkout!(account: account, user: user, amount_cents: 1500, user_ip: '1.1.1.1')
      end.to raise_error(Ai::Payments::PaytrService::Error, /parse failed/)
    end

    it 'raises error when paytr token is missing' do
      stub_request(:post, 'https://www.paytr.com/odeme/api/get-token')
        .to_return(
          status: 200,
          body: { status: 'success', token: '' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect do
        service.create_checkout!(account: account, user: user, amount_cents: 1500, user_ip: '1.1.1.1')
      end.to raise_error(Ai::Payments::PaytrService::Error, /token is missing/)
    end
  end

  describe '#process_callback!' do
    it 'raises invalid payload when callback status is unsupported' do
      expect do
        service.process_callback!(payload: {
          merchant_oid: 'OID_BAD_STATUS',
          status: 'processing',
          total_amount: '100',
          hash: callback_hash(merchant_oid: 'OID_BAD_STATUS', status: 'processing', total_amount: '100')
        })
      end.to raise_error(Ai::Payments::PaytrService::InvalidPayloadError, /status is invalid/)
    end

    it 'raises invalid payload when merchant oid format is invalid' do
      expect do
        service.process_callback!(payload: {
          merchant_oid: 'OID INVALID!',
          status: 'success',
          total_amount: '100',
          hash: callback_hash(merchant_oid: 'OID INVALID!', status: 'success', total_amount: '100')
        })
      end.to raise_error(Ai::Payments::PaytrService::InvalidPayloadError, /merchant_oid format is invalid/)
    end

    it 'returns order_not_found for unknown merchant oid' do
      result = service.process_callback!(payload: {
        merchant_oid: 'UNKNOWN_OID',
        status: 'success',
        total_amount: '100',
        hash: callback_hash(merchant_oid: 'UNKNOWN_OID', status: 'success', total_amount: '100')
      })

      expect(result[:result]).to eq('order_not_found')
      expect(result[:merchant_oid]).to eq('UNKNOWN_OID')
    end

    it 'raises invalid signature for incorrect hash' do
      order = AiPaymentOrder.create!(
        account: account,
        user: user,
        provider: 'paytr',
        merchant_oid: 'OID_BAD_HASH',
        status: :pending,
        amount_cents: 1000,
        currency: 'USD',
        payment_amount_cents: 1200,
        payment_currency: 'USD',
        vat_rate: 0.2,
        fx_rate: 1.0
      )

      expect do
        service.process_callback!(payload: {
          merchant_oid: order.merchant_oid,
          status: 'success',
          total_amount: '1200',
          hash: 'invalid-hash'
        })
      end.to raise_error(Ai::Payments::PaytrService::InvalidSignatureError)
    end

    it 'credits wallet once and marks order paid on successful callback' do
      order = AiPaymentOrder.create!(
        account: account,
        user: user,
        provider: 'paytr',
        merchant_oid: 'OID_SUCCESS_1',
        status: :pending,
        amount_cents: 1500,
        currency: 'USD',
        payment_amount_cents: 1800,
        payment_currency: 'USD',
        vat_rate: 0.2,
        fx_rate: 1.0
      )

      result = service.process_callback!(payload: {
        merchant_oid: order.merchant_oid,
        status: 'success',
        total_amount: '1800',
        hash: callback_hash(merchant_oid: order.merchant_oid, status: 'success', total_amount: '1800')
      })

      expect(result[:result]).to eq('paid')
      expect(order.reload).to be_paid
      expect(wallet.reload.balance_cents).to eq(2500)
      expect(AiTransaction.where(account_id: account.id, provider: 'paytr', provider_ref: order.merchant_oid, kind: :topup).count).to eq(1)
    end

    it 'marks order failed_validation and does not credit wallet when total amount is below expected' do
      order = AiPaymentOrder.create!(
        account: account,
        user: user,
        provider: 'paytr',
        merchant_oid: 'OID_LOW_TOTAL_1',
        status: :pending,
        amount_cents: 1200,
        currency: 'USD',
        payment_amount_cents: 1440,
        payment_currency: 'USD',
        vat_rate: 0.2,
        fx_rate: 1.0
      )

      before_balance = wallet.reload.balance_cents

      result = service.process_callback!(payload: {
        merchant_oid: order.merchant_oid,
        status: 'success',
        total_amount: '1300',
        hash: callback_hash(merchant_oid: order.merchant_oid, status: 'success', total_amount: '1300')
      })

      expect(result[:result]).to eq('failed_validation')
      expect(order.reload).to be_failed
      expect(order.fail_reason_code).to eq('validation_error')
      expect(wallet.reload.balance_cents).to eq(before_balance)
      expect(AiTransaction.where(account_id: account.id, provider: 'paytr', provider_ref: order.merchant_oid, kind: :topup).count).to eq(0)
    end

    it 'does not credit wallet and marks order failed on failed callback' do
      order = AiPaymentOrder.create!(
        account: account,
        user: user,
        provider: 'paytr',
        merchant_oid: 'OID_FAIL_1',
        status: :pending,
        amount_cents: 2000,
        currency: 'USD',
        payment_amount_cents: 2400,
        payment_currency: 'USD',
        vat_rate: 0.2,
        fx_rate: 1.0
      )

      before_balance = wallet.reload.balance_cents
      before_tx_count = AiTransaction.where(account_id: account.id, kind: :topup).count

      result = service.process_callback!(payload: {
        merchant_oid: order.merchant_oid,
        status: 'failed',
        total_amount: '2400',
        hash: callback_hash(merchant_oid: order.merchant_oid, status: 'failed', total_amount: '2400'),
        failed_reason_code: '99',
        failed_reason_msg: 'insufficient'
      })

      expect(result[:result]).to eq('failed')
      expect(order.reload).to be_failed
      expect(wallet.reload.balance_cents).to eq(before_balance)
      expect(AiTransaction.where(account_id: account.id, kind: :topup).count).to eq(before_tx_count)
    end

    it 'is idempotent for duplicate success callback' do
      order = AiPaymentOrder.create!(
        account: account,
        user: user,
        provider: 'paytr',
        merchant_oid: 'OID_DUP_1',
        status: :pending,
        amount_cents: 500,
        currency: 'USD',
        payment_amount_cents: 600,
        payment_currency: 'USD',
        vat_rate: 0.2,
        fx_rate: 1.0
      )

      payload = {
        merchant_oid: order.merchant_oid,
        status: 'success',
        total_amount: '600',
        hash: callback_hash(merchant_oid: order.merchant_oid, status: 'success', total_amount: '600')
      }

      first = service.process_callback!(payload: payload)
      second = service.process_callback!(payload: payload)

      expect(first[:result]).to eq('paid')
      expect(second[:result]).to eq('already_processed')
      expect(order.reload).to be_paid
      expect(AiTransaction.where(account_id: account.id, provider: 'paytr', provider_ref: order.merchant_oid, kind: :topup).count).to eq(1)
    end
  end
end
