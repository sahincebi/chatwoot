module Ai
  module Tools
    class CheckDemoAvailability < BaseTool
      def self.tool_name
        'check_demo_availability'
      end

      def self.tool_schema
        {
          type: 'function',
          name: tool_name,
          description: 'Check demo availability for a given date.',
          parameters: {
            type: 'object',
            properties: {
              date: { type: 'string', description: 'Date in YYYY-MM-DD' },
              tz: { type: 'string', description: 'IANA timezone' }
            },
            required: %w[date tz]
          },
          strict: true
        }
      end

      def self.required_params
        %w[date tz]
      end

      def self.param_types
        {
          'date' => String,
          'tz' => String
        }
      end

      def self.execute(account:, args:, **_context)
        zone = ActiveSupport::TimeZone[args['tz']] || Time.zone
        tomorrow = zone.today + 1
        return { error: 'date_not_allowed', message: 'only_tomorrow', tool: tool_name } if args['date'] != tomorrow.strftime('%F')

        # TODO: Replace with real Google Calendar availability lookup.
        {
          status: 'ok',
          tool: tool_name,
          date: args['date'],
          timezone: args['tz'],
          slots: ['15:00-16:00', '16:00-17:00']
        }
      end
    end
  end
end
