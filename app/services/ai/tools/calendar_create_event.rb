module Ai
  module Tools
    class CalendarCreateEvent < BaseTool
      def self.tool_name
        'calendar_create_event'
      end

      def self.tool_schema
        {
          type: 'function',
          function: {
            name: tool_name,
            description: 'Create a calendar event.',
            parameters: {
              type: 'object',
              properties: {
                start_time: { type: 'string', description: 'ISO8601 start time' },
                end_time: { type: 'string', description: 'ISO8601 end time' },
                timezone: { type: 'string', description: 'IANA timezone' },
                summary: { type: 'string', description: 'Event title' },
                description: { type: 'string', description: 'Event description' },
                calendar_id: { type: 'string', description: 'Calendar id' }
              },
              required: %w[start_time end_time summary timezone]
            }
          }
        }
      end

      def self.required_params
        %w[start_time end_time summary timezone]
      end

      def self.param_types
        {
          'start_time' => String,
          'end_time' => String,
          'timezone' => String,
          'summary' => String
        }
      end

      def self.execute(account:, args:, **_context)
        {
          status: 'ok',
          tool: tool_name,
          event: {
            id: "event_#{SecureRandom.hex(4)}",
            summary: args['summary'],
            description: args['description'],
            start_time: args['start_time'],
            end_time: args['end_time'],
            timezone: args['timezone']
          }
        }
      end
    end
  end
end
