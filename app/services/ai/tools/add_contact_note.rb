module Ai
  module Tools
    class AddContactNote < BaseTool
      def self.tool_name
        'add_contact_note'
      end

      def self.tool_schema
        {
          type: 'function',
          name: tool_name,
          description: 'Add a note to the contact profile of the current conversation.',
          parameters: {
            type: 'object',
            properties: {
              note: { type: 'string', description: 'The note content to save for the contact.' }
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

        contact = conversation.contact
        return { error: 'contact_missing', message: 'contact_missing' } unless contact

        note = args['note'].to_s.strip
        return { error: 'invalid_tool_arguments', message: 'note_required' } if note.blank?

        created_note = contact.notes.create!(
          account: account,
          user: account.ai_agent,
          content: note
        )

        {
          status: 'ok',
          tool: tool_name,
          note_id: created_note.id,
          contact_id: contact.id,
          note_preview: note.truncate(120)
        }
      end
    end
  end
end
