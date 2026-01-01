module Ai
  module Tools
    class BaseTool
      def self.tool_name
        raise NotImplementedError
      end

      def self.tool_schema
        raise NotImplementedError
      end

      def self.required_params
        []
      end

      def self.param_types
        {}
      end

      def self.call(account:, args:, **context)
        validation = validate_args(args)
        return validation if validation[:error].present?

        execute(account: account, args: args, **context)
      end

      def self.execute(account:, args:, **_context)
        raise NotImplementedError
      end

      def self.validate_args(args)
        args ||= {}
        missing = required_params.reject { |key| args[key].present? }
        type_errors = param_types.each_with_object({}) do |(key, klass), errors|
          next unless args[key].present?
          next if args[key].is_a?(klass)

          errors[key] = { expected: klass.name, actual: args[key].class.name }
        end

        return { error: 'invalid_tool_arguments', missing: missing, type_errors: type_errors } if missing.any? || type_errors.any?

        {}
      end
    end
  end
end
