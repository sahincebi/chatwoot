module Ai
  module Tools
    class CloseConversationLog < BaseTool
      def self.tool_name
        'close_conversation_log'
      end

      def self.tool_schema
        {
          type: 'function',
          function: {
            name: tool_name,
            description: 'Log a close conversation request and optionally resolve it.',
            parameters: {
              type: 'object',
              properties: {
                reason: { type: 'string', description: 'Reason for closing' },
                thread_id: { type: 'string', description: 'Optional thread id' }
              },
              required: %w[reason]
            }
          }
        }
      end

      def self.required_params
        %w[reason]
      end

      def self.param_types
        {
          'reason' => String
        }
      end

      def self.execute(account:, args:, conversation: nil, message: nil)
        Rails.logger.info(
          "[AI_REPLY] close_conversation_log account_id=#{account.id} conversation_id=#{conversation&.id} message_id=#{message&.id} reason=#{args['reason']}"
        )

        if conversation&.open?
          conversation.update!(status: :resolved)
        end

        {
          status: 'ok',
          tool: tool_name,
          reason: args['reason']
        }
      end
    end
  end
end
