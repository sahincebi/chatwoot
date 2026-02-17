module Ai
  module Tools
    class AddPrivateNoteToConversation < BaseTool
      def self.tool_name
        'add_private_note_to_conversation'
      end

      def self.tool_schema
        {
          type: 'function',
          name: tool_name,
          description: 'Add a private note to the current conversation for human agents.',
          parameters: {
            type: 'object',
            properties: {
              note: { type: 'string', description: 'Private note text.' }
            },
            required: ['note']
          },
          strict: true
        }
      end

      def self.required_params
        ['note']
      end

      def self.param_types
        {
          'note' => String
        }
      end

      def self.execute(account:, args:, conversation: nil, **_context)
        return { error: 'conversation_missing', message: 'conversation_missing' } unless conversation

        note = args['note'].to_s.strip
        return { error: 'invalid_tool_arguments', message: 'note_required' } if note.blank?

        message = conversation.messages.create!(
          account: account,
          inbox: conversation.inbox,
          sender: account.ai_agent,
          message_type: :outgoing,
          content: note,
          private: true
        )

        {
          status: 'ok',
          tool: tool_name,
          private_message_id: message.id
        }
      end
    end
  end
end
