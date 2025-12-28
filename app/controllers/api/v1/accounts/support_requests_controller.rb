class Api::V1::Accounts::SupportRequestsController < Api::V1::Accounts::BaseController
  def create
    support_hq_account = find_support_hq_account
    return render_support_error('Support HQ account is not configured') unless support_hq_account

    support_inbox = find_support_hq_inbox(support_hq_account)
    return render_support_error('Support HQ inbox is not provisioned') unless support_inbox
    ensure_support_flag(support_inbox)

    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: support_inbox,
      contact_attributes: support_contact_attributes,
      source_id: support_source_id,
      hmac_verified: false
    ).perform

    conversation = ConversationBuilder.new(
      params: ActionController::Parameters.new(
        status: 'open',
        additional_attributes: support_additional_attributes
      ),
      contact_inbox: contact_inbox
    ).perform

    Messages::MessageBuilder.new(Current.user, conversation, message_params).perform if message_present?

    render json: { ok: true, ticket_id: conversation.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def find_support_hq_account
    raw_id = InstallationConfig.get_value('SUPPORT_HQ_ACCOUNT_ID')
    hq_id = raw_id.to_i
    return if hq_id <= 0

    Account.find_by(id: hq_id)
  end

  def find_support_hq_inbox(account)
    inbox_name = InstallationConfig.get_value('SUPPORT_HQ_INBOX_NAME').presence || 'Support'
    account.inboxes.where('lower(name) = ?', inbox_name.downcase).first
  end

  def support_ticket_source
    InstallationConfig.get_value('SUPPORT_TICKET_SOURCE').presence || 'internal_support_form'
  end

  def support_source_id
    "#{support_ticket_source}_#{Current.account.id}_#{Current.user.id}_#{Time.zone.now.to_i}"
  end

  def support_contact_attributes
    {
      name: Current.user.name.presence || Current.user.email,
      email: Current.user.email,
      additional_attributes: {
        support_requested_by_account_id: Current.account.id,
        support_requested_by_account_name: Current.account.name
      }
    }
  end

  def support_additional_attributes
    attrs = {
      support_requested_by_user_id: Current.user.id,
      support_requested_by_user_email: Current.user.email,
      support_requested_by_user_name: Current.user.name,
      support_requested_by_account_id: Current.account.id,
      support_requested_by_account_name: Current.account.name,
      support_source: support_ticket_source
    }

    attrs[:support_subject] = params[:subject] if params[:subject].present?
    attrs[:support_category] = params[:category] if params[:category].present?
    attrs[:support_priority] = params[:priority] if params[:priority].present?
    attrs
  end

  def message_params
    ActionController::Parameters.new(
      content: params.dig(:message, :content).to_s,
      message_type: 'incoming',
      attachments: params.dig(:message, :attachments)
    )
  end

  def message_present?
    params.dig(:message, :content).present? || params.dig(:message, :attachments).present?
  end

  def ensure_support_flag(inbox)
    attrs = inbox.additional_attributes.is_a?(Hash) ? inbox.additional_attributes : {}
    return if attrs['is_support'] == true

    inbox.update!(additional_attributes: attrs.merge('is_support' => true))
  end

  def render_support_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
