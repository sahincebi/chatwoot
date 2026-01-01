module Ai
  module Tools
    class ToolRegistry
      TOOL_CONFIG = {
        'calendar_query_availability' => {
          klass: CalendarQueryAvailability,
          category: 'calendar',
          requires_calendar: true
        },
        'calendar_create_event' => {
          klass: CalendarCreateEvent,
          category: 'calendar',
          requires_calendar: true
        },
        'check_demo_availability' => {
          klass: CheckDemoAvailability,
          category: 'demo',
          requires_calendar: true
        },
        'create_demo_appointment' => {
          klass: CreateDemoAppointment,
          category: 'demo',
          requires_calendar: true
        },
        'send_demo_email' => {
          klass: SendDemoEmail,
          category: 'email',
          requires_calendar: false
        },
        'close_conversation_log' => {
          klass: CloseConversationLog,
          category: 'conversation',
          requires_calendar: false
        }
      }.freeze

      def self.tool_schemas_for(account)
        return [] unless account.tool_calling_enabled?

        TOOL_CONFIG.keys.filter_map do |tool_name|
          config = TOOL_CONFIG[tool_name]
          next unless allowed_by_policy?(account, tool_name, config[:category])

          schema = config[:klass].tool_schema
          name = schema[:name] || schema['name']
          unless name.present?
            Rails.logger.info("[AI_REPLY] invalid_tool_schema tool=#{tool_name} reason=missing_name")
            next
          end

          schema
        end
      end

      def self.execute(account:, tool_call:, conversation: nil, message: nil)
        tool_name = tool_call[:name].to_s
        config = TOOL_CONFIG[tool_name]
        category = config&.fetch(:category, nil)
        return { error: 'tool_not_allowed', error_class: 'policy', tool: tool_name, category: category } unless config
        return { error: 'tool_not_allowed', error_class: 'policy', tool: tool_name, category: category } unless allowed_by_policy?(account, tool_name, category)

        if config[:requires_calendar] && !google_calendar_configured?(account)
          return {
            error: 'calendar_not_configured',
            error_class: 'integration',
            error_message: 'calendar_integration_missing',
            tool: tool_name,
            category: category
          }
        end

        args = parse_arguments(tool_call[:arguments])
        if args[:error].present?
          return {
            error: args[:error],
            error_class: 'invalid_arguments',
            error_message: args[:parse_error],
            tool: tool_name,
            category: category,
            args: args
          }
        end

        result = config[:klass].call(account: account, args: args, conversation: conversation, message: message)
        if result.is_a?(Hash) && result[:error].present?
          return {
            error: result[:error],
            error_class: 'tool_error',
            error_message: result[:message],
            tool: tool_name,
            category: category,
            args: args,
            content: result
          }
        end

        {
          tool: tool_name,
          category: category,
          args: args,
          content: result
        }
      end

      def self.google_calendar_configured?(account)
        integration = account.google_calendar_integration
        integration&.enabled? && integration.refresh_token.present?
      end

      def self.allowed_by_policy?(account, tool_name, category)
        policy = account.ai_tool_policy_with_defaults
        allowed_tools = policy['allowed_tools'] || {}
        return true if allowed_tools[category] == true

        allowed_tools[tool_name.to_s] == true
      end

      def self.parse_arguments(raw_arguments)
        return {} if raw_arguments.blank?

        if raw_arguments.is_a?(Hash)
          return raw_arguments.deep_stringify_keys
        end

        JSON.parse(raw_arguments.to_s).deep_stringify_keys
      rescue JSON::ParserError => e
        { error: 'invalid_tool_arguments', parse_error: e.message.to_s.truncate(200) }
      end
    end
  end
end
