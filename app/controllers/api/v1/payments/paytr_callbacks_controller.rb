class Api::V1::Payments::PaytrCallbacksController < ActionController::Base
  skip_before_action :verify_authenticity_token
  before_action :enforce_ip_allowlist!

  def create
    result = Ai::Payments::PaytrService.new.process_callback!(payload: callback_payload)
    Rails.logger.info("[AI_PAYTR] callback_result result=#{result[:result]} merchant_oid=#{result[:merchant_oid]} remote_ip=#{request.remote_ip}")
    render plain: 'OK'
  rescue Ai::Payments::PaytrService::InvalidPayloadError => e
    Rails.logger.error("[AI_PAYTR] callback_payload_error error=#{e.message} remote_ip=#{request.remote_ip}")
    render plain: 'FAIL', status: :unprocessable_entity
  rescue Ai::Payments::PaytrService::InvalidSignatureError => e
    Rails.logger.error("[AI_PAYTR] callback_signature_error error=#{e.message} remote_ip=#{request.remote_ip}")
    render plain: 'FAIL', status: :unauthorized
  rescue Ai::Payments::PaytrService::ConfigurationError => e
    Rails.logger.error("[AI_PAYTR] callback_config_error error=#{e.message}")
    render plain: 'FAIL', status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[AI_PAYTR] callback_error class=#{e.class} error=#{e.message}")
    render plain: 'FAIL', status: :internal_server_error
  end

  private

  def callback_payload
    {
      merchant_oid: params[:merchant_oid],
      status: params[:status],
      total_amount: params[:total_amount],
      payment_amount: params[:payment_amount],
      currency: params[:currency],
      payment_type: params[:payment_type],
      test_mode: params[:test_mode],
      hash: params[:hash],
      failed_reason_code: params[:failed_reason_code],
      failed_reason_msg: params[:failed_reason_msg]
    }
  end

  def enforce_ip_allowlist!
    allowed_ips = ENV.fetch('PAYTR_CALLBACK_IP_ALLOWLIST', '')
                     .split(',')
                     .map(&:strip)
                     .reject(&:blank?)
    return if allowed_ips.empty?
    return if allowed_ips.include?(request.remote_ip.to_s)

    Rails.logger.error("[AI_PAYTR] callback_ip_blocked remote_ip=#{request.remote_ip}")
    render plain: 'FAIL', status: :forbidden
  end
end
