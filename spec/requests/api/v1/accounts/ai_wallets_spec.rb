require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::AiWallets' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/:account_id/ai_wallet' do
    it 'returns unauthorized for unauthenticated request' do
      get "/api/v1/accounts/#{account.id}/ai_wallet"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns wallet details for admin' do
      AiWallet.find_or_create_by!(account_id: account.id) do |wallet|
        wallet.balance_cents = 0
        wallet.currency = 'USD'
        wallet.status = :active
      end

      get "/api/v1/accounts/#{account.id}/ai_wallet", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['balance_cents']).to eq(0)
      expect(json['currency']).to eq('USD')
      expect(json['status']).to eq('active')
    end

    it 'returns low_balance true when balance is below threshold' do
      AiWallet.create!(account_id: account.id, balance_cents: 100, currency: 'USD', status: :active)

      get "/api/v1/accounts/#{account.id}/ai_wallet", headers: admin.create_new_auth_token

      json = response.parsed_body
      expect(json['low_balance']).to be(true)
      expect(json['low_balance_threshold_cents']).to eq(AiWallet::LOW_BALANCE_THRESHOLD_CENTS)
    end

    it 'returns low_balance false when balance meets threshold' do
      AiWallet.create!(account_id: account.id, balance_cents: AiWallet::LOW_BALANCE_THRESHOLD_CENTS, currency: 'USD', status: :active)

      get "/api/v1/accounts/#{account.id}/ai_wallet", headers: admin.create_new_auth_token

      expect(response.parsed_body['low_balance']).to be(false)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/ai_wallet/transactions' do
    it 'returns unauthorized for unauthenticated request' do
      get "/api/v1/accounts/#{account.id}/ai_wallet/transactions"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized for non-admin user' do
      get "/api/v1/accounts/#{account.id}/ai_wallet/transactions", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns paginated transactions for admin' do
      AiTransaction.create!(account: account, kind: :topup, amount_cents: 1000, currency: 'USD',
                            provider: 'paytr', provider_ref: 'oid-1', meta: { 'note' => 'first' })
      AiTransaction.create!(account: account, kind: :debit, amount_cents: 200, currency: 'USD', provider: 'system')

      get "/api/v1/accounts/#{account.id}/ai_wallet/transactions", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['data'].length).to eq(2)
      expect(json['meta']['total_count']).to eq(2)
      expect(json['meta']['per_page']).to eq(25)
      topup = json['data'].find { |t| t['kind'] == 'topup' }
      expect(topup['note']).to eq('first')
      expect(topup['provider_ref']).to eq('oid-1')
    end

    it 'filters by kind' do
      AiTransaction.create!(account: account, kind: :topup, amount_cents: 1000, currency: 'USD', provider: 'system')
      AiTransaction.create!(account: account, kind: :debit, amount_cents: 200, currency: 'USD', provider: 'system')

      get "/api/v1/accounts/#{account.id}/ai_wallet/transactions",
          params: { kind: 'topup' },
          headers: admin.create_new_auth_token

      json = response.parsed_body
      expect(json['data'].length).to eq(1)
      expect(json['data'].first['kind']).to eq('topup')
    end

    it 'does not return transactions from other accounts' do
      other_account = create(:account)
      AiTransaction.create!(account: other_account, kind: :topup, amount_cents: 5000, currency: 'USD', provider: 'system')

      get "/api/v1/accounts/#{account.id}/ai_wallet/transactions", headers: admin.create_new_auth_token

      expect(response.parsed_body['data']).to eq([])
    end
  end

  describe 'GET /api/v1/accounts/:account_id/ai_wallet/usage_logs' do
    it 'returns unauthorized for unauthenticated request' do
      get "/api/v1/accounts/#{account.id}/ai_wallet/usage_logs"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized for non-admin user' do
      get "/api/v1/accounts/#{account.id}/ai_wallet/usage_logs", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns paginated usage logs with totals' do
      AiUsageLog.create!(account: account, input_tokens: 0, output_tokens: 0, cost_cents: 0, provider_cost_cents: 0, total_tokens: 100, billed_cost_cents: 50, currency: 'USD')
      AiUsageLog.create!(account: account, input_tokens: 0, output_tokens: 0, cost_cents: 0, provider_cost_cents: 0, total_tokens: 200, billed_cost_cents: 80, currency: 'USD')

      get "/api/v1/accounts/#{account.id}/ai_wallet/usage_logs", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['data'].length).to eq(2)
      expect(json['meta']['totals']['total_tokens']).to eq(300)
      expect(json['meta']['totals']['billed_cost_cents']).to eq(130)
    end

    it 'filters by date range' do
      old_log = AiUsageLog.create!(account: account, input_tokens: 0, output_tokens: 0, cost_cents: 0, provider_cost_cents: 0, total_tokens: 100, billed_cost_cents: 50, currency: 'USD')
      old_log.update_column(:created_at, 60.days.ago)
      AiUsageLog.create!(account: account, input_tokens: 0, output_tokens: 0, cost_cents: 0, provider_cost_cents: 0, total_tokens: 200, billed_cost_cents: 80, currency: 'USD')

      from = 7.days.ago.to_date.iso8601
      to = Date.current.iso8601
      get "/api/v1/accounts/#{account.id}/ai_wallet/usage_logs",
          params: { from: from, to: to },
          headers: admin.create_new_auth_token

      json = response.parsed_body
      expect(json['data'].length).to eq(1)
      expect(json['meta']['totals']['total_tokens']).to eq(200)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/ai_wallet/topup' do
    it 'returns unauthorized for unauthenticated request' do
      post "/api/v1/accounts/#{account.id}/ai_wallet/topup", params: { amount_cents: 1000 }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized for non-admin user' do
      post "/api/v1/accounts/#{account.id}/ai_wallet/topup",
           params: { amount_cents: 1000 },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns forbidden for account admin (manual topup disabled)' do
      post "/api/v1/accounts/#{account.id}/ai_wallet/topup",
           params: { amount_cents: 1000 },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns forbidden even for invalid amount (endpoint disabled)' do
      post "/api/v1/accounts/#{account.id}/ai_wallet/topup",
           params: { amount_cents: 0 },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/ai_wallet/paytr_checkout' do
    let(:headers) { admin.create_new_auth_token }

    before do
      stub_request(:post, 'https://www.paytr.com/odeme/api/get-token')
        .to_return(
          status: 200,
          body: { status: 'success', token: 'test-token' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'creates a pending paytr order and returns checkout url' do
      with_modified_env(
        'PAYTR_MERCHANT_ID' => 'merchant-id',
        'PAYTR_MERCHANT_KEY' => 'merchant-key',
        'PAYTR_MERCHANT_SALT' => 'merchant-salt',
        'PAYTR_OK_URL' => 'https://example.com/paytr/ok',
        'PAYTR_FAIL_URL' => 'https://example.com/paytr/fail',
        'PAYTR_TEST_MODE' => '1',
        'MINIMUM_TOPUP_USD' => '10',
        'PAYMENTS_VAT_RATE' => '0.2'
      ) do
        post "/api/v1/accounts/#{account.id}/ai_wallet/paytr_checkout",
             params: { amount_cents: 1500, note: 'test checkout' },
             headers: headers
      end

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['checkout_url']).to eq('https://www.paytr.com/odeme/test-token')
      expect(body['merchant_oid']).to be_present
      expect(AiPaymentOrder.where(account_id: account.id).count).to eq(1)
      order = AiPaymentOrder.last
      expect(order).to be_pending
      expect(order.payment_currency).to eq('USD')
      expect(order.payment_amount_cents).to eq(1800)
      expect(order.fx_rate.to_f).to eq(1.0)

      expect(a_request(:post, 'https://www.paytr.com/odeme/api/get-token')
        .with { |request| request.body.include?('currency=USD') }).to have_been_made
      expect(a_request(:post, 'https://www.paytr.com/odeme/api/get-token')
        .with { |request| request.body.include?('payment_amount=1800') }).to have_been_made
    end
  end
end
