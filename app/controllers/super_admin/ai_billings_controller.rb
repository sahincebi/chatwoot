class SuperAdmin::AiBillingsController < SuperAdmin::ApplicationController
  before_action :set_account, only: [:show, :topup]

  def index
    @days = sanitized_days(params[:days], default: 30)
    @pricing_config = Ai::PricingConfig.current
    @accounts = Account.order(:id).includes(:ai_wallet)
    account_ids = @accounts.map(&:id)

    @wallets_by_account_id = AiWallet.where(account_id: account_ids).index_by(&:account_id)
    @usage_totals_by_account_id = usage_totals_for(account_ids)
    @topup_totals_by_account_id = AiTransaction.where(account_id: account_ids, kind: :topup).group(:account_id).sum(:amount_cents)
    @global_totals = aggregate_usage_totals(AiUsageLog.all)
    kpi_scope = AiUsageLog.where(created_at: @days.days.ago.beginning_of_day..Time.current.end_of_day)
    @kpi_summary = Ai::KpiSummaryService.new(scope: kpi_scope, days: @days)
    @kpi_totals = @kpi_summary.totals
    @kpi_daily = @kpi_summary.daily_breakdown
    @kpi_top_accounts = @kpi_summary.top_accounts(limit: 10)
    @low_balance_accounts = @accounts.select do |account|
      wallet = @wallets_by_account_id[account.id]
      wallet.present? && wallet.low_balance?
    end
  end

  def update_pricing
    input_cost_per_1m = parse_decimal(params[:input_cost_per_1m])
    output_cost_per_1m = parse_decimal(params[:output_cost_per_1m])
    billing_multiplier = parse_decimal(params[:billing_multiplier])

    if input_cost_per_1m.nil? || output_cost_per_1m.nil? || billing_multiplier.nil? || billing_multiplier <= 0
      redirect_to super_admin_ai_billings_path, alert: 'Pricing values are invalid. Use numeric values and multiplier > 0.'
      return
    end

    InstallationConfig.set_value('AI_INPUT_COST_PER_1M', input_cost_per_1m, locked: false)
    InstallationConfig.set_value('AI_OUTPUT_COST_PER_1M', output_cost_per_1m, locked: false)
    InstallationConfig.set_value('AI_BILLING_MULTIPLIER', billing_multiplier, locked: false)

    redirect_to super_admin_ai_billings_path, notice: 'AI pricing settings updated.'
  end

  def show
    @days = sanitized_days(params[:days], default: 30)
    @wallet = find_or_create_wallet(@account)
    @pricing_config = Ai::PricingConfig.current
    @usage_totals = aggregate_usage_totals(@account.ai_usage_logs)
    @recent_transactions = @account.ai_transactions.order(created_at: :desc).limit(100)
    @recent_usage_logs = @account.ai_usage_logs.order(created_at: :desc).limit(100)
    kpi_scope = @account.ai_usage_logs.where(created_at: @days.days.ago.beginning_of_day..Time.current.end_of_day)
    @kpi_summary = Ai::KpiSummaryService.new(scope: kpi_scope, days: @days)
    @kpi_totals = @kpi_summary.totals
    @kpi_daily = @kpi_summary.daily_breakdown
  end

  def topup
    amount_cents = parse_amount(params[:amount_cents])
    if amount_cents.nil? || amount_cents <= 0
      redirect_to super_admin_ai_billing_path(@account), alert: 'Topup amount must be a positive integer.'
      return
    end

    provider_ref = params[:provider_ref].presence || "super-admin-#{SecureRandom.hex(6)}"
    note = params[:note].presence
    wallet = find_or_create_wallet(@account)

    existing = AiTransaction.find_by(account_id: @account.id, provider: 'super_admin', provider_ref: provider_ref)
    if existing
      redirect_to super_admin_ai_billing_path(@account), notice: "Topup already applied (ref: #{provider_ref})."
      return
    end

    ActiveRecord::Base.transaction do
      wallet.with_lock do
        wallet.balance_cents += amount_cents
        wallet.save!
      end

      AiTransaction.create!(
        account_id: @account.id,
        kind: :topup,
        amount_cents: amount_cents,
        currency: wallet.currency,
        provider: 'super_admin',
        provider_ref: provider_ref,
        meta: { note: note, by_super_admin_id: current_super_admin.id }.compact
      )
    end

    redirect_to super_admin_ai_billing_path(@account), notice: "Topup applied: #{amount_cents} cents."
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  def find_or_create_wallet(account)
    AiWallet.find_or_create_by!(account_id: account.id) do |wallet|
      wallet.balance_cents = 0
      wallet.currency = 'USD'
      wallet.status = :active
    end
  rescue ActiveRecord::RecordNotUnique
    AiWallet.find_by!(account_id: account.id)
  end

  def parse_amount(value)
    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_decimal(value)
    return nil if value.nil?

    parsed = Float(value)
    return nil unless parsed.finite?
    return nil if parsed.negative?

    parsed
  rescue ArgumentError, TypeError
    nil
  end

  def usage_totals_for(account_ids)
    return {} if account_ids.empty?

    AiUsageLog.where(account_id: account_ids)
              .group(:account_id)
              .pluck(
                :account_id,
                Arel.sql('COALESCE(SUM(provider_cost_cents), 0)'),
                Arel.sql('COALESCE(SUM(billed_cost_cents), COALESCE(SUM(cost_cents), 0))'),
                Arel.sql('COALESCE(SUM(total_tokens), 0)')
              )
              .each_with_object({}) do |(account_id, provider_cost_cents, billed_cost_cents, total_tokens), result|
                result[account_id] = {
                  provider_cost_cents: provider_cost_cents.to_i,
                  billed_cost_cents: billed_cost_cents.to_i,
                  total_tokens: total_tokens.to_i,
                  profit_cents: billed_cost_cents.to_i - provider_cost_cents.to_i
                }
              end
  end

  def aggregate_usage_totals(scope)
    provider_cost_cents = scope.sum(:provider_cost_cents).to_i
    billed_cost_cents = scope.sum(:billed_cost_cents).to_i
    total_tokens = scope.sum(:total_tokens).to_i

    {
      provider_cost_cents: provider_cost_cents,
      billed_cost_cents: billed_cost_cents,
      total_tokens: total_tokens,
      profit_cents: billed_cost_cents - provider_cost_cents
    }
  end

  def sanitized_days(value, default:)
    parsed = value.to_i
    return default unless parsed.positive?

    [[parsed, 7].max, 365].min
  end
end
