require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::AiSettings' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/:account_id/ai_settings' do
    it 'returns unauthorized for unauthenticated request' do
      get "/api/v1/accounts/#{account.id}/ai_settings"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns ai settings and masks secrets' do
      AiIntegration.create!(
        account: account,
        provider: 'google_calendar',
        enabled: true,
        settings: { 'calendar_id' => 'primary', 'timezone' => 'Europe/Istanbul' },
        refresh_token: 'token-1234567890'
      )

      get "/api/v1/accounts/#{account.id}/ai_settings", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['ai_integrations']['google_calendar']['has_refresh_token']).to be(true)
      expect(json['ai_integrations']['google_calendar'].keys).not_to include('refresh_token')
    end
  end

  describe 'PUT /api/v1/accounts/:account_id/ai_settings' do
    it 'updates ai settings for admin' do
      payload = {
        ai_enabled: false,
        ai_prompt_id: 'pmpt_123',
        ai_prompt_version: 4,
        ai_tool_policy: {
          enabled: true,
          allowed_tools: { 'calendar' => true },
          limits: { max_tools_per_turn: 3, max_total_steps: 8 }
        }
      }

      put "/api/v1/accounts/#{account.id}/ai_settings",
          params: payload,
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      account.reload
      expect(account.ai_enabled).to be(false)
      expect(account.ai_prompt_id).to eq('pmpt_123')
      expect(account.ai_prompt_version).to eq(4)
      expect(account.ai_tool_policy_with_defaults['allowed_tools']['calendar']).to be(true)
    end

    it 'returns unauthorized for non-admin user' do
      put "/api/v1/accounts/#{account.id}/ai_settings",
          params: { ai_enabled: false },
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PUT /api/v1/accounts/:account_id/ai_integrations/google_calendar' do
    it 'sets and clears refresh_token safely' do
      put "/api/v1/accounts/#{account.id}/ai_integrations/google_calendar",
          params: { enabled: true, refresh_token: 'token-1234567890', calendar_id: 'primary' },
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['has_refresh_token']).to be(true)

      put "/api/v1/accounts/#{account.id}/ai_integrations/google_calendar",
          params: { refresh_token: '' },
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['has_refresh_token']).to be(false)
    end
  end
end
