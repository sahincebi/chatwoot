class Api::V1::Accounts::AiWalletsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin!

  def show
    wallet = find_or_create_wallet
    render json: wallet_payload(wallet)
  end

  def topup
    amount_cents = parse_amount(params[:amount_cents])
    if amount_cents.nil? || amount_cents <= 0
      render json: { error: 'amount_cents must be a positive integer' }, status: :unprocessable_entity
      return
    end

    wallet = find_or_create_wallet
    provider_ref = params[:provider_ref].presence
    note = params[:note].presence

    if provider_ref.present?
      existing = AiTransaction.find_by(account_id: Current.account.id, provider: 'admin', provider_ref: provider_ref)
      if existing
        render json: topup_payload(wallet.reload, existing)
        return
      end
    end

    transaction = nil
    ActiveRecord::Base.transaction do
      wallet.with_lock do
        wallet.balance_cents += amount_cents
        wallet.save!
      end
      transaction = AiTransaction.create!(
        account_id: Current.account.id,
        kind: :topup,
        amount_cents: amount_cents,
        provider: 'admin',
        provider_ref: provider_ref,
        meta: { note: note, by_user_id: Current.user.id }.compact
      )
    end

    render json: topup_payload(wallet.reload, transaction)
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

  def topup_payload(wallet, transaction)
    {
      balance_cents: wallet.balance_cents,
      currency: wallet.currency,
      transaction: {
        id: transaction.id,
        kind: transaction.kind,
        amount_cents: transaction.amount_cents,
        provider: transaction.provider,
        provider_ref: transaction.provider_ref,
        created_at: transaction.created_at
      }
    }
  end
end
