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

  def stub_google_success(event_id: 'evt_1', meet_link: 'https://meet.google.com/abc-defg-hij')
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
          id: event_id,
          htmlLink: "https://calendar.google.com/event?eid=#{event_id}",
          conferenceData: {
            entryPoints: [
              { entryPointType: 'video', uri: meet_link }
            ]
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'creates a calendar event and returns proof fields' do
    integration
    stub_google_success(event_id: 'evt_1', meet_link: 'https://meet.google.com/abc-defg-hij')

    with_modified_env(
      'GOOGLE_OAUTH_CLIENT_ID' => 'client-id',
      'GOOGLE_OAUTH_CLIENT_SECRET' => 'client-secret'
    ) do
      result = described_class.call(account: account, args: args)
      expect(result[:status]).to eq('ok')
      expect(result[:event_id]).to eq('evt_1')
      expect(result[:html_link]).to eq('https://calendar.google.com/event?eid=evt_1')
      expect(result[:meet_link]).to eq('https://meet.google.com/abc-defg-hij')
      expect(result[:calendar_id]).to eq('primary')
      expect(result[:timezone]).to eq('Europe/Istanbul')
    end
  end

  it 'parses time range without duration' do
    integration
    stub_google_success(event_id: 'evt_range', meet_link: 'https://meet.google.com/range')

    range_args = args.merge('time' => '15-16')
    with_modified_env(
      'GOOGLE_OAUTH_CLIENT_ID' => 'client-id',
      'GOOGLE_OAUTH_CLIENT_SECRET' => 'client-secret'
    ) do
      result = described_class.call(account: account, args: range_args)
      zone = Time.find_zone('Europe/Istanbul')
      expect(result[:start_time]).to eq(zone.parse('2026-01-02 15:00').iso8601)
      expect(result[:end_time]).to eq(zone.parse('2026-01-02 16:00').iso8601)
      expect(result[:duration_minutes]).to eq(60)
    end
  end

  it 'parses time range with minutes' do
    integration
    stub_google_success(event_id: 'evt_short', meet_link: 'https://meet.google.com/short')

    range_args = args.merge('time' => '15:00-15:30')
    with_modified_env(
      'GOOGLE_OAUTH_CLIENT_ID' => 'client-id',
      'GOOGLE_OAUTH_CLIENT_SECRET' => 'client-secret'
    ) do
      result = described_class.call(account: account, args: range_args)
      zone = Time.find_zone('Europe/Istanbul')
      expect(result[:start_time]).to eq(zone.parse('2026-01-02 15:00').iso8601)
      expect(result[:end_time]).to eq(zone.parse('2026-01-02 15:30').iso8601)
      expect(result[:duration_minutes]).to eq(30)
    end
  end

  it 'uses duration_minutes when only start time is provided' do
    integration
    stub_google_success(event_id: 'evt_duration', meet_link: 'https://meet.google.com/duration')

    duration_args = args.merge('time' => '15:00', 'duration_minutes' => 30)
    with_modified_env(
      'GOOGLE_OAUTH_CLIENT_ID' => 'client-id',
      'GOOGLE_OAUTH_CLIENT_SECRET' => 'client-secret'
    ) do
      result = described_class.call(account: account, args: duration_args)
      zone = Time.find_zone('Europe/Istanbul')
      expect(result[:start_time]).to eq(zone.parse('2026-01-02 15:00').iso8601)
      expect(result[:end_time]).to eq(zone.parse('2026-01-02 15:30').iso8601)
      expect(result[:duration_minutes]).to eq(30)
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

  it 'uses integration settings when env credentials are missing' do
    integration.update!(
      settings: {
        'calendar_id' => 'primary',
        'timezone' => 'Europe/Istanbul',
        'client_id' => 'settings-client',
        'client_secret' => 'settings-secret'
      }
    )

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
          id: 'evt_settings',
          htmlLink: 'https://calendar.google.com/event?eid=settings',
          hangoutLink: 'https://meet.google.com/settings-meet'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    with_modified_env('GOOGLE_OAUTH_CLIENT_ID' => nil, 'GOOGLE_OAUTH_CLIENT_SECRET' => nil) do
      result = described_class.call(account: account, args: args)
      expect(result[:status]).to eq('ok')
      expect(result[:event_id]).to eq('evt_settings')
      expect(result[:meet_link]).to eq('https://meet.google.com/settings-meet')
    end
  end

  it 'returns oauth_client_missing when credentials are missing' do
    integration.update!(settings: { 'calendar_id' => 'primary', 'timezone' => 'Europe/Istanbul' })

    with_modified_env('GOOGLE_OAUTH_CLIENT_ID' => nil, 'GOOGLE_OAUTH_CLIENT_SECRET' => nil) do
      result = described_class.call(account: account, args: args)
      expect(result[:status]).to eq('error')
      expect(result[:error_code]).to eq('oauth_client_missing')
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
