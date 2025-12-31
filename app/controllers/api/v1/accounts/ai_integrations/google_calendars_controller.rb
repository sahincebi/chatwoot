class Api::V1::Accounts::AiIntegrations::GoogleCalendarsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin!

  def update
    integration = Current.account.ai_integrations.find_or_initialize_by(provider: 'google_calendar')
    apply_params(integration)
    integration.save!
    render json: integration_payload(integration)
  end

  private

  def ensure_admin!
    return if Current.user.is_a?(SuperAdmin)

    check_admin_authorization?
  end

  def integration_params
    params.permit(:enabled, :refresh_token, :calendar_id, :timezone)
  end

  def apply_params(integration)
    attrs = integration_params
    if attrs.key?(:enabled)
      integration.enabled = ActiveModel::Type::Boolean.new.cast(attrs[:enabled])
    end

    if attrs.key?(:refresh_token)
      integration.refresh_token = attrs[:refresh_token].presence
    end

    settings = integration.settings || {}
    settings['calendar_id'] = attrs[:calendar_id] if attrs.key?(:calendar_id)
    settings['timezone'] = attrs[:timezone] if attrs.key?(:timezone)
    integration.settings = settings
  end

  def integration_payload(integration)
    {
      provider: integration.provider,
      enabled: integration.enabled,
      has_refresh_token: integration.refresh_token.present?,
      settings: {
        calendar_id: integration.settings['calendar_id'],
        timezone: integration.settings['timezone']
      }
    }
  end
end
