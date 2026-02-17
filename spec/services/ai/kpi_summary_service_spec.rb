require 'rails_helper'

RSpec.describe Ai::KpiSummaryService do
  let(:account_one) { create(:account) }
  let(:account_two) { create(:account) }

  before do
    create_usage(account: account_one, total_tokens: 1000, provider_cost_cents: 20, billed_cost_cents: 80, created_at: 1.day.ago)
    create_usage(account: account_one, total_tokens: 500, provider_cost_cents: 10, billed_cost_cents: 40, created_at: 1.day.ago)
    create_usage(account: account_two, total_tokens: 750, provider_cost_cents: 15, billed_cost_cents: 45, created_at: Time.current)
  end

  it 'calculates totals and averages' do
    summary = described_class.new(scope: AiUsageLog.where(account_id: [account_one.id, account_two.id]), days: 30)

    totals = summary.totals
    expect(totals[:provider_cost_cents]).to eq(45)
    expect(totals[:billed_cost_cents]).to eq(165)
    expect(totals[:profit_cents]).to eq(120)
    expect(totals[:total_tokens]).to eq(2250)
    expect(totals[:request_count]).to eq(3)
    expect(totals[:avg_cents_per_request]).to eq(55.0)
  end

  it 'returns daily breakdown and top accounts' do
    summary = described_class.new(scope: AiUsageLog.where(account_id: [account_one.id, account_two.id]), days: 30)
    daily = summary.daily_breakdown
    top_accounts = summary.top_accounts(limit: 2)

    expect(daily).not_to be_empty
    expect(daily.first).to include(:day, :request_count, :total_tokens, :profit_cents)
    expect(top_accounts.first[:account_id]).to eq(account_one.id)
    expect(top_accounts.first[:billed_cost_cents]).to eq(120)
  end

  def create_usage(account:, total_tokens:, provider_cost_cents:, billed_cost_cents:, created_at:)
    AiUsageLog.create!(
      account: account,
      total_tokens: total_tokens,
      input_tokens: total_tokens / 2,
      output_tokens: total_tokens / 2,
      provider_cost_cents: provider_cost_cents,
      billed_cost_cents: billed_cost_cents,
      cost_cents: billed_cost_cents,
      currency: 'USD',
      created_at: created_at,
      updated_at: created_at
    )
  end
end
