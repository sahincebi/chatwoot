module Ai
  module Tools
    class CreateDemoAppointment < BaseTool
      def self.tool_name
        'create_demo_appointment'
      end

      def self.tool_schema
        {
          type: 'function',
          function: {
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
            }
          }
        }
      end

      def self.required_params
        %w[date time name phone email tz]
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
        return { error: 'invalid_time', message: 'time_format_invalid', tool: tool_name } unless args['time'].match?(/\A\d{2}:\d{2}\z/)

        # TODO: Replace with real Google Calendar create event flow.
        {
          status: 'ok',
          tool: tool_name,
          event_id: 'dummy',
          meet_link: 'https://meet.google.com/dummy-meet',
          date: args['date'],
          time: args['time'],
          timezone: args['tz']
        }
      end
    end
  end
end
