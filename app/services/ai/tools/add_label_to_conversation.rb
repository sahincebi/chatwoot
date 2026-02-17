module Ai
  module Tools
    class AddLabelToConversation < BaseTool
      def self.tool_name
        'add_label_to_conversation'
      end

      def self.tool_schema
        {
          type: 'function',
          name: tool_name,
          description: 'Add one or more labels to the current conversation.',
          parameters: {
            type: 'object',
            properties: {
              labels: {
                type: 'array',
                description: 'List of labels to add. Use lowercase words.',
                items: { type: 'string' }
              },
              label: {
                type: 'string',
                description: 'Single label to add when labels array is not provided.'
              }
            }
          },
          strict: true
        }
      end

      def self.execute(account:, args:, conversation: nil, **_context)
        return { error: 'conversation_missing', message: 'conversation_missing' } unless conversation

        labels = normalized_labels(args)
        return { error: 'invalid_tool_arguments', message: 'label_required' } if labels.empty?

        created_labels = []
        labels.each do |label|
          begin
            record = account.labels.find_or_create_by!(title: label)
            created_labels << record.title
          rescue ActiveRecord::RecordInvalid
            return { error: 'invalid_tool_arguments', message: 'invalid_label', details: { label: label } }
          end
        end

        conversation.add_labels(created_labels)

        {
          status: 'ok',
          tool: tool_name,
          labels: conversation.reload.label_list.sort
        }
      end

      def self.normalized_labels(args)
        values = []
        values.concat(Array(args['labels']))
        values << args['label']
        values
          .compact
          .map { |value| value.to_s.strip.downcase }
          .reject(&:blank?)
          .uniq
      end
    end
  end
end
