require 'rails_helper'

RSpec.describe 'Super Admin Application Config API', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns redirect' do
        get '/super_admin/app_config'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      before do
        InstallationConfig.set_value('FB_APP_ID', 'TESTVALUE', locked: false)
      end

      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=facebook'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('TESTVALUE')
      end
    end
  end

  describe 'POST /super_admin/app_config' do
    it 'casts boolean typed configs before persisting' do
      sign_in(super_admin, scope: :super_admin)

      get '/super_admin/app_config?config=general'
      csrf_token = response.body.match(/name="csrf-token" content="([^"]+)"/)&.captures&.first
      expect(csrf_token).to be_present

      post '/super_admin/app_config?config=general',
           params: { app_config: { ENABLE_ACCOUNT_SIGNUP: 'true' } },
           headers: { 'X-CSRF-Token' => csrf_token }

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(super_admin_settings_path)
      expect(InstallationConfig.find_by(name: 'ENABLE_ACCOUNT_SIGNUP').value).to eq(true)
    end
  end
end
