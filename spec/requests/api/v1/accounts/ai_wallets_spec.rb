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
