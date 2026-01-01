module Ai
  module Tools
    class CalendarQueryAvailability < BaseTool
      def self.tool_name
        'calendar_query_availability'
      end

      def self.tool_schema
        {
          type: 'function',
          name: tool_name,
          description: 'Query calendar availability for a time range.',
          parameters: {
            type: 'object',
            properties: {
              start_time: { type: 'string', description: 'ISO8601 start time' },
              end_time: { type: 'string', description: 'ISO8601 end time' },
              timezone: { type: 'string', description: 'IANA timezone' },
              calendar_id: { type: 'string', description: 'Calendar id' }
            },
            required: %w[start_time end_time timezone]
          },
          strict: false
        }
      end

      def self.required_params
        %w[start_time end_time timezone]
      end

      def self.param_types
        {
          'start_time' => String,
          'end_time' => String,
          'timezone' => String
        }
      end

      def self.execute(account:, args:, **_context)
        {
          status: 'ok',
          tool: tool_name,
          slots: [],
          timezone: args['timezone'],
          requested_range: {
            start_time: args['start_time'],
            end_time: args['end_time']
          }
        }
      end
    end
  end
end
