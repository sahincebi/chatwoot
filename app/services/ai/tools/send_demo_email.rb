module Ai
  module Tools
    class SendDemoEmail < BaseTool
      def self.tool_name
        'send_demo_email'
      end

      def self.tool_schema
        {
          type: 'function',
          function: {
            name: tool_name,
            description: 'Send a demo confirmation email.',
            parameters: {
              type: 'object',
              properties: {
                to_name: { type: 'string', description: 'Recipient name' },
                to_email: { type: 'string', description: 'Recipient email' },
                date: { type: 'string', description: 'Date in YYYY-MM-DD' },
                time: { type: 'string', description: 'Time in HH:MM' },
                meet_link: { type: 'string', description: 'Meeting link' }
              },
              required: %w[to_name to_email date time meet_link]
            }
          }
        }
      end

      def self.required_params
        %w[to_name to_email date time meet_link]
      end

      def self.param_types
        {
          'to_name' => String,
          'to_email' => String,
          'date' => String,
          'time' => String,
          'meet_link' => String
        }
      end

      def self.execute(account:, args:, **_context)
        AiDemoMailer.demo_email(
          to_name: args['to_name'],
          to_email: args['to_email'],
          date: args['date'],
          time: args['time'],
          meet_link: args['meet_link']
        ).deliver_later

        { status: 'ok', tool: tool_name, sent: true }
      rescue StandardError => e
        { error: 'email_send_failed', message: e.message.to_s.truncate(200), tool: tool_name }
      end
    end
  end
end
