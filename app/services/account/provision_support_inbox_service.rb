class Account::ProvisionSupportInboxService
  def initialize(account:)
    @account = account
  end

  def call
    return unless auto_provision_enabled?

    inbox_name = support_inbox_name
    existing_inbox = support_inbox(inbox_name)
    if existing_inbox
      ensure_support_flag(existing_inbox)
      Rails.logger.info("[SupportInboxProvision] account_id=#{@account.id} inbox_id=#{existing_inbox.id} status=exists")
      return
    end

    ActiveRecord::Base.transaction do
      channel = @account.api_channels.create!(additional_attributes: { internal_support: true })
      inbox_attrs = {
        name: inbox_name,
        channel: channel,
        greeting_enabled: false,
        enable_email_collect: false,
        csat_survey_enabled: false
      }
      inbox_attrs[:additional_attributes] = { 'is_support' => true }
      inbox_attrs[:is_support] = true if support_column_available?
      inbox = @account.inboxes.create!(inbox_attrs)

      @account.account_users.administrator.pluck(:user_id).each do |user_id|
        InboxMember.find_or_create_by!(inbox: inbox, user_id: user_id)
      end

      Rails.logger.info("[SupportInboxProvision] account_id=#{@account.id} inbox_id=#{inbox.id} status=created")
    end
  end

  private

  def auto_provision_enabled?
    value = GlobalConfig.get('SUPPORT_INBOX_AUTO_PROVISION')['SUPPORT_INBOX_AUTO_PROVISION']
    value.nil? ? true : value
  end

  def support_inbox_name
    GlobalConfig.get('SUPPORT_INBOX_NAME')['SUPPORT_INBOX_NAME'].presence || 'Destek'
  end

  def support_inbox(name)
    @account.inboxes.where('lower(name) = ?', name.downcase).first
  end

  def ensure_support_flag(inbox)
    attrs = inbox.additional_attributes.is_a?(Hash) ? inbox.additional_attributes : {}
    needs_attr_update = attrs['is_support'] != true
    needs_column_update = support_column_available? && inbox.is_support != true
    return unless needs_attr_update || needs_column_update

    update_params = {}
    update_params[:additional_attributes] = attrs.merge('is_support' => true) if needs_attr_update
    update_params[:is_support] = true if needs_column_update
    inbox.update!(update_params)
  end

  def support_column_available?
    Inbox.column_names.include?('is_support')
  end
end
