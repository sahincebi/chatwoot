module Ai
  class KpiSummaryService
    DEFAULT_DAYS = 30

    def initialize(scope: AiUsageLog.all, days: DEFAULT_DAYS)
      @scope = scope
      @days = days.to_i.positive? ? days.to_i : DEFAULT_DAYS
    end

    def totals
      provider_cost_cents = @scope.sum(:provider_cost_cents).to_i
      billed_cost_cents = @scope.sum(:billed_cost_cents).to_i
      total_tokens = @scope.sum(:total_tokens).to_i
      request_count = @scope.count

      {
        provider_cost_cents: provider_cost_cents,
        billed_cost_cents: billed_cost_cents,
        profit_cents: billed_cost_cents - provider_cost_cents,
        total_tokens: total_tokens,
        request_count: request_count,
        avg_cents_per_request: request_count.positive? ? (billed_cost_cents.to_f / request_count).round(2) : 0.0,
        avg_cents_per_1k_tokens: total_tokens.positive? ? ((billed_cost_cents.to_f / total_tokens) * 1000).round(4) : 0.0
      }
    end

    def daily_breakdown
      grouped = @scope
                .where(created_at: period_range)
                .group(Arel.sql('DATE(created_at)'))
                .order(Arel.sql('DATE(created_at) DESC'))
                .pluck(
                  Arel.sql('DATE(created_at)'),
                  Arel.sql('COUNT(*)'),
                  Arel.sql('COALESCE(SUM(total_tokens), 0)'),
                  Arel.sql('COALESCE(SUM(provider_cost_cents), 0)'),
                  Arel.sql('COALESCE(SUM(billed_cost_cents), 0)')
                )

      grouped.map do |day, requests, tokens, provider_cost, billed_cost|
        {
          day: day,
          request_count: requests.to_i,
          total_tokens: tokens.to_i,
          provider_cost_cents: provider_cost.to_i,
          billed_cost_cents: billed_cost.to_i,
          profit_cents: billed_cost.to_i - provider_cost.to_i
        }
      end
    end

    def top_accounts(limit: 10)
      @scope
        .joins(:account)
        .group('accounts.id', 'accounts.name')
        .order(Arel.sql('COALESCE(SUM(ai_usage_logs.billed_cost_cents),0) DESC'))
        .limit(limit)
        .pluck(
          'accounts.id',
          'accounts.name',
          Arel.sql('COUNT(ai_usage_logs.id)'),
          Arel.sql('COALESCE(SUM(ai_usage_logs.total_tokens),0)'),
          Arel.sql('COALESCE(SUM(ai_usage_logs.provider_cost_cents),0)'),
          Arel.sql('COALESCE(SUM(ai_usage_logs.billed_cost_cents),0)')
        )
        .map do |account_id, account_name, requests, tokens, provider_cost, billed_cost|
          {
            account_id: account_id,
            account_name: account_name,
            request_count: requests.to_i,
            total_tokens: tokens.to_i,
            provider_cost_cents: provider_cost.to_i,
            billed_cost_cents: billed_cost.to_i,
            profit_cents: billed_cost.to_i - provider_cost.to_i
          }
        end
    end

    private

    def period_range
      @days.days.ago.beginning_of_day..Time.current.end_of_day
    end
  end
end
