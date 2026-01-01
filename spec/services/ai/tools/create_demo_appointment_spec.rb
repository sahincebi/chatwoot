require 'rails_helper'

RSpec.describe Ai::Tools::CreateDemoAppointment do
  let(:account) { create(:account) }
  let(:integration) do
    AiIntegration.create!(
      account: account,
      provider: 'google_calendar',
      enabled: true,
      refresh_token: 'refresh-token',
      settings: { 'calendar_id' => 'primary', 'timezone' => 'Europe/Istanbul' }
    )
  end

  let(:args) do
    {
      'date' => '2026-01-02',
      'time' => '15:00',
      'name' => 'Test User',
      'phone' => '+905551112233',
      'email' => 'test@example.com',
      'tz' => 'Europe/Istanbul'
    }
  end

  it 'creates a calendar event and returns proof fields' do
    integration
    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .to_return(
        status: 200,
        body: { access_token: 'access-token', expires_in: 3600 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:post, 'https://www.googleapis.com/calendar/v3/calendars/primary/events?conferenceDataVersion=1')
      .to_return(
        status: 200,
        body: {
          id: 'evt_1',
          htmlLink: 'https://calendar.google.com/event?eid=1',
          conferenceData: {
            entryPoints: [
              { entryPointType: 'video', uri: 'https://meet.google.com/abc-defg-hij' }
            ]
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    with_modified_env(
      'GOOGLE_OAUTH_CLIENT_ID' => 'client-id',
      'GOOGLE_OAUTH_CLIENT_SECRET' => 'client-secret'
    ) do
      result = described_class.call(account: account, args: args)
      expect(result[:status]).to eq('ok')
      expect(result[:event_id]).to eq('evt_1')
      expect(result[:html_link]).to eq('https://calendar.google.com/event?eid=1')
      expect(result[:meet_link]).to eq('https://meet.google.com/abc-defg-hij')
      expect(result[:calendar_id]).to eq('primary')
      expect(result[:timezone]).to eq('Europe/Istanbul')
    end
  end

  it 'returns refresh_token_missing when token is absent' do
    integration.update!(refresh_token: nil)

    with_modified_env(
      'GOOGLE_OAUTH_CLIENT_ID' => 'client-id',
      'GOOGLE_OAUTH_CLIENT_SECRET' => 'client-secret'
    ) do
      result = described_class.call(account: account, args: args)
      expect(result[:status]).to eq('error')
      expect(result[:error_code]).to eq('refresh_token_missing')
      expect(WebMock).not_to have_requested(:post, 'https://oauth2.googleapis.com/token')
    end
  end

  it 'returns google_api_error when calendar insert fails' do
    integration
    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .to_return(
        status: 200,
        body: { access_token: 'access-token', expires_in: 3600 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:post, 'https://www.googleapis.com/calendar/v3/calendars/primary/events?conferenceDataVersion=1')
      .to_return(
        status: 400,
        body: { error: { message: 'invalid request' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    with_modified_env(
      'GOOGLE_OAUTH_CLIENT_ID' => 'client-id',
      'GOOGLE_OAUTH_CLIENT_SECRET' => 'client-secret'
    ) do
      result = described_class.call(account: account, args: args)
      expect(result[:status]).to eq('error')
      expect(result[:error_code]).to eq('google_api_error')
    end
  end
end
