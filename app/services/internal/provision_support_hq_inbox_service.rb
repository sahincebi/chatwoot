class Internal::ProvisionSupportHqInboxService
  def call
    account = support_hq_account
    return unless account

    existing_inbox = find_existing_support_inbox(account)
    if existing_inbox
      ensure_support_flag(existing_inbox)
      ensure_admin_membership(account, existing_inbox)
      normalize_support_inbox_name(existing_inbox)
      Rails.logger.info("[SupportHqProvision] account_id=#{account.id} inbox_id=#{existing_inbox.id} status=exists")
      return existing_inbox
    end

    inbox_name = support_hq_inbox_name
    name_matched_inbox = account.inboxes.where('lower(trim(name)) = ?', inbox_name.downcase).first
    if name_matched_inbox
      ensure_support_flag(name_matched_inbox)
      ensure_admin_membership(account, name_matched_inbox)
      normalize_support_inbox_name(name_matched_inbox)
      Rails.logger.info("[SupportHqProvision] account_id=#{account.id} inbox_id=#{name_matched_inbox.id} status=matched_name")
      return name_matched_inbox
    end

    ActiveRecord::Base.transaction do
      channel = account.api_channels.create!(additional_attributes: { internal_support_hq: true })
      inbox_attrs = {
        name: inbox_name,
        channel: channel,
        greeting_enabled: false,
        enable_email_collect: false,
        csat_survey_enabled: false
      }
      inbox_attrs[:additional_attributes] = { 'is_support' => true }
      inbox_attrs[:is_support] = true if support_column_available?
      inbox = account.inboxes.create!(inbox_attrs)

      ensure_admin_membership(account, inbox)

      Rails.logger.info("[SupportHqProvision] account_id=#{account.id} inbox_id=#{inbox.id} status=created")
      inbox
    end
  end

  private

  def support_hq_account
    raw_id = InstallationConfig.get_value('SUPPORT_HQ_ACCOUNT_ID')
    hq_id = raw_id.to_i
    raise ArgumentError, 'SUPPORT_HQ_ACCOUNT_ID must be a positive integer' if hq_id <= 0

    account = Account.find_by(id: hq_id)
    raise ActiveRecord::RecordNotFound, 'Support HQ account not found' unless account

    account
  end

  def support_hq_inbox_name
    (InstallationConfig.get_value('SUPPORT_HQ_INBOX_NAME').presence || 'Support').to_s.strip
  end

  def find_existing_support_inbox(account)
    support_inboxes = support_inboxes_scope(account).order(updated_at: :desc, id: :desc).to_a
    return if support_inboxes.empty?

    primary = support_inboxes.first
    extra = support_inboxes.drop(1)
    demote_extra_support_inboxes(extra) if extra.any?
    primary
  end

  def support_inboxes_scope(account)
    if support_column_available?
      account.inboxes.where("inboxes.is_support = TRUE OR COALESCE(additional_attributes->>'is_support','false') = 'true'")
    else
      account.inboxes.where("COALESCE(additional_attributes->>'is_support','false') = 'true'")
    end
  end

  def demote_extra_support_inboxes(inboxes)
    inboxes.each do |inbox|
      update_params = {}
      update_params[:is_support] = false if support_column_available? && inbox.is_support

      attrs = inbox.additional_attributes.is_a?(Hash) ? inbox.additional_attributes : {}
      if attrs['is_support'] == true
        update_params[:additional_attributes] = attrs.merge('is_support' => false)
      end

      update_params[:updated_at] = Time.zone.now if update_params.any?
      inbox.update_columns(update_params) if update_params.any?
    end
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

  def normalize_support_inbox_name(inbox)
    return unless inbox.name.blank?

    inbox_name = support_hq_inbox_name
    return if inbox_name.blank?

    inbox.update!(name: inbox_name)
  end

  def ensure_admin_membership(account, inbox)
    account.account_users.administrator.pluck(:user_id).each do |user_id|
      InboxMember.find_or_create_by!(inbox: inbox, user_id: user_id)
    end
  end

  def support_column_available?
    Inbox.column_names.include?('is_support')
  end
end
