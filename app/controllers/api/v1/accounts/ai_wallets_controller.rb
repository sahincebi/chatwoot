class Api::V1::Accounts::AiWalletsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin!

  RESULTS_PER_PAGE = 25

  def show
    wallet = find_or_create_wallet
    render json: wallet_payload(wallet)
  end

  def topup
    render json: { error: 'manual topup is disabled; use paytr_checkout' }, status: :forbidden
  end

  def transactions
    scope = Current.account.ai_transactions.order(created_at: :desc)
    scope = scope.where(kind: params[:kind]) if params[:kind].present? && AiTransaction.kinds.key?(params[:kind])
    page = scope.page(params[:page]).per(RESULTS_PER_PAGE)
    render json: {
      data: page.map { |t| transaction_payload(t) },
      meta: {
        total_count: scope.count,
        current_page: page.current_page,
        total_pages: page.total_pages,
        per_page: RESULTS_PER_PAGE
      }
    }
  end

  def usage_logs
    scope = Current.account.ai_usage_logs.order(created_at: :desc)
    range = parse_date_range(params[:from], params[:to])
    scope = scope.where(created_at: range) if range
    page = scope.page(params[:page]).per(RESULTS_PER_PAGE)
    render json: {
      data: page.map { |l| usage_log_payload(l) },
      meta: {
        total_count: scope.count,
        current_page: page.current_page,
        total_pages: page.total_pages,
        per_page: RESULTS_PER_PAGE,
        totals: usage_totals(scope)
      }
    }
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
      status: wallet.status,
      low_balance: wallet.low_balance?,
      low_balance_threshold_cents: AiWallet::LOW_BALANCE_THRESHOLD_CENTS
    }
  end

  def transaction_payload(transaction)
    {
      id: transaction.id,
      kind: transaction.kind,
      amount_cents: transaction.amount_cents,
      currency: transaction.currency,
      provider: transaction.provider,
      provider_ref: transaction.provider_ref,
      note: transaction.meta.is_a?(Hash) ? transaction.meta['note'] : nil,
      created_at: transaction.created_at
    }
  end

  def usage_log_payload(log)
    {
      id: log.id,
      conversation_id: log.conversation_id,
      message_id: log.message_id,
      model: log.model,
      input_tokens: log.input_tokens,
      output_tokens: log.output_tokens,
      total_tokens: log.total_tokens,
      billed_cost_cents: log.billed_cost_cents,
      currency: log.currency,
      created_at: log.created_at
    }
  end

  def usage_totals(scope)
    {
      total_tokens: scope.sum(:total_tokens).to_i,
      billed_cost_cents: scope.sum(:billed_cost_cents).to_i
    }
  end

  def parse_date_range(from, to)
    return nil if from.blank? || to.blank?

    from_date = Date.parse(from).beginning_of_day
    to_date = Date.parse(to).end_of_day
    from_date..to_date
  rescue ArgumentError, TypeError
    nil
  end
end
