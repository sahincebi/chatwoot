class SuperAdmin::SettingsController < SuperAdmin::ApplicationController
  def show; end

  def refresh
    Internal::CheckNewVersionsJob.perform_now
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_settings_path, notice: 'Instance status refreshed'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def provision_support_inboxes
    Internal::ProvisionSupportInboxesJob.perform_later
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_settings_path, notice: 'Support inbox provisioning started'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def provision_support_hq_inbox
    Internal::ProvisionSupportHqInboxJob.perform_later(current_super_admin.id)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_settings_path, notice: 'Support HQ inbox provisioning started'
    # rubocop:enable Rails/I18nLocaleTexts
  end
end
