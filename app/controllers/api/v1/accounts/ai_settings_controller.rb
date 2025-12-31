class Api::V1::Accounts::AiSettingsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin!

  def show
    render json: ai_settings_payload
  end

  def update
    attrs = ai_settings_params.to_h
    normalized = normalize_ai_settings(attrs)
    return if performed?

    Current.account.update!(normalized)
    render json: ai_settings_payload
  end

  private

  def ensure_admin!
    return if Current.user.is_a?(SuperAdmin)

    check_admin_authorization?
  end

  def ai_settings_params
    params.permit(:ai_enabled, :ai_prompt_id, :ai_prompt_version, ai_tool_policy: {})
  end

  def normalize_ai_settings(attrs)
    if attrs.key?('ai_enabled')
      attrs['ai_enabled'] = ActiveModel::Type::Boolean.new.cast(attrs['ai_enabled'])
    end

    if attrs.key?('ai_prompt_version')
      attrs['ai_prompt_version'] = attrs['ai_prompt_version'].to_i
      if attrs['ai_prompt_version'] < 1
        render json: { error: 'ai_prompt_version must be >= 1' }, status: :unprocessable_entity
        return attrs
      end
    end

    if attrs.key?('ai_tool_policy')
      policy = normalize_tool_policy(attrs['ai_tool_policy'])
      unless valid_tool_policy?(policy)
        render json: { error: 'invalid tool policy' }, status: :unprocessable_entity
        return attrs
      end
      attrs['ai_tool_policy'] = policy
    end

    attrs
  end

  def normalize_tool_policy(policy_param)
    policy = policy_param.is_a?(ActionController::Parameters) ? policy_param.to_unsafe_h : policy_param
    return nil unless policy.is_a?(Hash)

    policy = policy.deep_stringify_keys
    if policy.key?('enabled')
      policy['enabled'] = ActiveModel::Type::Boolean.new.cast(policy['enabled'])
    end
    if policy['allowed_tools'].is_a?(Hash)
      policy['allowed_tools'] = policy['allowed_tools'].transform_values do |value|
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
    limits = policy['limits']
    if limits.is_a?(Hash)
      limits = limits.deep_stringify_keys
      if limits.key?('max_tools_per_turn')
        limits['max_tools_per_turn'] = limits['max_tools_per_turn'].to_i
      end
      if limits.key?('max_total_steps')
        limits['max_total_steps'] = limits['max_total_steps'].to_i
      end
      policy['limits'] = limits
    end

    policy
  end

  def valid_tool_policy?(policy)
    return false unless policy.is_a?(Hash)

    if policy.key?('enabled') && ![true, false].include?(policy['enabled'])
      return false
    end

    if policy.key?('allowed_tools') && !policy['allowed_tools'].is_a?(Hash)
      return false
    end

    if policy.key?('limits')
      limits = policy['limits']
      return false unless limits.is_a?(Hash)
      if limits.key?('max_tools_per_turn')
        value = limits['max_tools_per_turn']
        return false unless value.is_a?(Integer) && value.between?(1, 10)
      end
      if limits.key?('max_total_steps')
        value = limits['max_total_steps']
        return false unless value.is_a?(Integer) && value.between?(1, 20)
      end
    end

    true
  end

  def ai_settings_payload
    integration = Current.account.google_calendar_integration
    {
      ai_enabled: Current.account.ai_enabled,
      ai_prompt_id: Current.account.ai_prompt_id,
      ai_prompt_version: Current.account.ai_prompt_version,
      ai_tool_policy: Current.account.ai_tool_policy_with_defaults,
      ai_integrations: {
        google_calendar: {
          enabled: integration&.enabled || false,
          has_refresh_token: integration&.refresh_token.present? || false,
          calendar_id: integration&.settings&.[]('calendar_id'),
          timezone: integration&.settings&.[]('timezone')
        }
      }
    }
  end
end
