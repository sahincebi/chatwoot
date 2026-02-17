module Ai
  module Tools
    class RemoveLabelFromConversation < BaseTool
      def self.tool_name
        'remove_label_from_conversation'
      end

      def self.tool_schema
        {
          type: 'function',
          name: tool_name,
          description: 'Remove one or more labels from the current conversation.',
          parameters: {
            type: 'object',
            properties: {
              labels: {
                type: 'array',
                description: 'List of labels to remove.',
                items: { type: 'string' }
              },
              label: {
                type: 'string',
                description: 'Single label to remove when labels array is not provided.'
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

        current = conversation.label_list.map(&:downcase)
        updated = current - labels
        conversation.update_labels(updated)

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
