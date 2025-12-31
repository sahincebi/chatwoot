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

    it 'tops up wallet and creates transaction' do
      post "/api/v1/accounts/#{account.id}/ai_wallet/topup",
           params: { amount_cents: 1000 },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      account.reload
      expect(account.ai_wallet.balance_cents).to eq(1000)
      expect(AiTransaction.where(account_id: account.id, kind: :topup).count).to eq(1)
    end

    it 'rejects invalid amount' do
      post "/api/v1/accounts/#{account.id}/ai_wallet/topup",
           params: { amount_cents: 0 },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'prevents duplicate topup with same provider_ref' do
      headers = admin.create_new_auth_token
      post "/api/v1/accounts/#{account.id}/ai_wallet/topup",
           params: { amount_cents: 2000, provider_ref: 'dup-1' },
           headers: headers

      expect(response).to have_http_status(:success)
      first_balance = account.reload.ai_wallet.balance_cents

      post "/api/v1/accounts/#{account.id}/ai_wallet/topup",
           params: { amount_cents: 2000, provider_ref: 'dup-1' },
           headers: headers

      expect(response).to have_http_status(:success)
      account.reload
      expect(account.ai_wallet.balance_cents).to eq(first_balance)
      expect(AiTransaction.where(account_id: account.id, provider: 'admin', provider_ref: 'dup-1').count).to eq(1)
    end
  end
end
