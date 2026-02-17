class Api::V1::Accounts::AiWalletsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin!

  def show
    wallet = find_or_create_wallet
    render json: wallet_payload(wallet)
  end

  def topup
    render json: { error: 'manual topup is disabled; use paytr_checkout' }, status: :forbidden
  end

  def paytr_checkout
    amount_cents = parse_amount(params[:amount_cents])
    if amount_cents.nil? || amount_cents <= 0
      render json: { error: 'amount_cents must be a positive integer' }, status: :unprocessable_entity
      return
    end

    result = Ai::Payments::PaytrService.new.create_checkout!(
      account: Current.account,
      user: Current.user,
      amount_cents: amount_cents,
      user_ip: request.remote_ip,
      note: params[:note].presence
    )

    render json: result
  rescue Ai::Payments::PaytrService::InvalidAmountError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Ai::Payments::PaytrService::ConfigurationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Ai::Payments::PaytrService::Error => e
    Rails.logger.error "[AI_PAYTR] checkout_error account_id=#{Current.account.id} user_id=#{Current.user.id} error=#{e.message}"
    render json: { error: 'PayTR checkout could not be created' }, status: :bad_gateway
  end

  private

  def ensure_admin!
    return if Current.user.is_a?(SuperAdmin)

    check_admin_authorization?
  end

  def parse_amount(value)
    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def find_or_create_wallet
    AiWallet.find_or_create_by!(account_id: Current.account.id) do |wallet|
      wallet.balance_cents = 0
      wallet.currency = 'USD'
      wallet.status = :active
    end
  rescue ActiveRecord::RecordNotUnique
    AiWallet.find_by!(account_id: Current.account.id)
  end

  def wallet_payload(wallet)
    {
      balance_cents: wallet.balance_cents,
      currency: wallet.currency,
      status: wallet.status
    }
  end

end
