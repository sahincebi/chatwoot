require 'net/http'
require 'cgi'
require 'securerandom'

module Ai
  module Tools
    class CreateDemoAppointment < BaseTool
      def self.tool_name
        'create_demo_appointment'
      end

      def self.tool_schema
        {
          type: 'function',
          name: tool_name,
          description: 'Create a demo appointment and return a meeting link.',
          parameters: {
            type: 'object',
            properties: {
              date: { type: 'string', description: 'Date in YYYY-MM-DD' },
              time: { type: 'string', description: 'Time in HH:MM' },
              name: { type: 'string', description: 'Full name' },
              phone: { type: 'string', description: 'Phone number' },
              email: { type: 'string', description: 'Email address' },
              tz: { type: 'string', description: 'IANA timezone' }
            },
            required: %w[date time name phone email tz]
          },
          strict: true
        }
      end

      def self.required_params
        %w[date time name phone email]
      end

      def self.param_types
        {
          'date' => String,
          'time' => String,
          'name' => String,
          'phone' => String,
          'email' => String,
          'tz' => String
        }
      end

      def self.execute(account:, args:, **_context)
        integration = account.google_calendar_integration
        return error_payload('calendar_integration_missing', 'calendar_integration_missing') unless integration&.enabled?
        return error_payload('refresh_token_missing', 'refresh_token_missing') if integration.refresh_token.blank?

        client_id = ENV['GOOGLE_OAUTH_CLIENT_ID']
        client_secret = ENV['GOOGLE_OAUTH_CLIENT_SECRET']
        if client_id.blank? || client_secret.blank?
          return error_payload('validation_error', 'google_oauth_credentials_missing')
        end

        calendar_id = integration.settings['calendar_id'].presence || 'primary'
        timezone = integration.settings['timezone'].presence || 'Europe/Istanbul'
        date = args['date']
        time = args['time']
        return error_payload('validation_error', 'date_missing') if date.blank?
        return error_payload('validation_error', 'time_format_invalid') unless time.match?(/\A\d{2}:\d{2}\z/)

        zone = ActiveSupport::TimeZone[timezone] || Time.zone
        start_time = zone.parse("#{date} #{time}")
        return error_payload('validation_error', 'datetime_parse_failed') unless start_time
        end_time = start_time + 1.hour

        access = fetch_access_token(integration.refresh_token, client_id, client_secret, integration)
        return error_payload('google_api_error', access[:message], details: access[:details]) unless access[:access_token].present?

        event = build_event_payload(args, start_time, end_time, timezone)
        response = insert_event(access[:access_token], calendar_id, event)
        return error_payload('google_api_error', response[:message], details: response[:details]) unless response[:success]

        {
          status: 'ok',
          tool: tool_name,
          date: date,
          time: "#{start_time.strftime('%H:%M')}-#{end_time.strftime('%H:%M')}",
          timezone: timezone,
          event_id: response[:event_id],
          html_link: response[:html_link],
          meet_link: response[:meet_link],
          calendar_id: calendar_id
        }
      end

      def self.error_payload(code, message, details: nil)
        {
          status: 'error',
          tool: tool_name,
          error: code,
          error_code: code,
          message: message,
          details: details
        }.compact
      end

      def self.fetch_access_token(refresh_token, client_id, client_secret, integration)
        uri = URI('https://oauth2.googleapis.com/token')
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: refresh_token,
          grant_type: 'refresh_token'
        )

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
        parsed = JSON.parse(response.body) rescue {}
        if response.code.to_i >= 400
          return {
            message: parsed['error_description'] || parsed['error'] || 'google_oauth_error',
            details: { http_status: response.code.to_i }
          }
        end

        access_token = parsed['access_token']
        expires_in = parsed['expires_in'].to_i
        if access_token.present?
          integration.update(
            access_token: access_token,
            expires_at: expires_in.positive? ? Time.current + expires_in.seconds : nil
          )
        end

        { access_token: access_token, expires_in: expires_in }
      rescue StandardError => e
        { message: 'google_oauth_error', details: { error_class: e.class.name } }
      end

      def self.build_event_payload(args, start_time, end_time, timezone)
        description = [
          "Name: #{args['name']}",
          "Phone: #{args['phone']}",
          "Email: #{args['email']}"
        ].join("\n")

        {
          summary: 'Demo Appointment',
          description: description,
          start: {
            dateTime: start_time.iso8601,
            timeZone: timezone
          },
          end: {
            dateTime: end_time.iso8601,
            timeZone: timezone
          },
          attendees: [{ email: args['email'] }],
          conferenceData: {
            createRequest: {
              requestId: SecureRandom.uuid
            }
          }
        }
      end

      def self.insert_event(access_token, calendar_id, event)
        url = "https://www.googleapis.com/calendar/v3/calendars/#{CGI.escape(calendar_id)}/events"
        uri = URI(url)
        uri.query = 'conferenceDataVersion=1'
        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{access_token}"
        request['Content-Type'] = 'application/json'
        request.body = event.to_json

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
        parsed = JSON.parse(response.body) rescue {}
        if response.code.to_i >= 400
          return {
            success: false,
            message: parsed.dig('error', 'message') || 'google_calendar_error',
            details: { http_status: response.code.to_i }
          }
        end

        meet_link = extract_meet_link(parsed)
        {
          success: true,
          event_id: parsed['id'],
          html_link: parsed['htmlLink'],
          meet_link: meet_link
        }
      rescue StandardError => e
        {
          success: false,
          message: 'google_calendar_error',
          details: { error_class: e.class.name }
        }
      end

      def self.extract_meet_link(parsed)
        entry_points = parsed.dig('conferenceData', 'entryPoints') || []
        video = entry_points.find { |entry| entry['entryPointType'] == 'video' }
        video&.dig('uri') || parsed['hangoutLink']
      end
    end
  end
end
