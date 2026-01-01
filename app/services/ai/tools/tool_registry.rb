module Ai
  module Tools
    class ToolRegistry
      TOOL_CLASSES = {
        'calendar_query_availability' => CalendarQueryAvailability,
        'calendar_create_event' => CalendarCreateEvent
      }.freeze

      def self.tool_schemas_for(account)
        return [] unless account.tool_calling_enabled?

        TOOL_CLASSES.keys.filter_map do |tool_name|
          next unless account.tool_allowed?(tool_name)

          TOOL_CLASSES[tool_name].tool_schema
        end
      end

      def self.execute(account:, tool_call:)
        tool_name = tool_call[:name].to_s
        tool_class = TOOL_CLASSES[tool_name]
        return { error: 'tool_not_allowed', tool: tool_name } unless tool_class
        return { error: 'tool_not_allowed', tool: tool_name } unless account.tool_allowed?(tool_name)

        if tool_name.start_with?('calendar_') && !google_calendar_configured?(account)
          return { error: 'calendar_not_configured', tool: tool_name }
        end

        args = parse_arguments(tool_call[:arguments])
        return args if args[:error].present?

        tool_class.call(account: account, args: args)
      end

      def self.google_calendar_configured?(account)
        integration = account.google_calendar_integration
        integration&.enabled? && integration.refresh_token.present?
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
