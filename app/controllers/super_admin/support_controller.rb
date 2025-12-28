class SuperAdmin::SupportController < SuperAdmin::ApplicationController
  before_action :set_support_context
  before_action :set_conversation, only: [:show, :reply]

  def index
    @conversations = support_conversations
                       .includes(:contact)
                       .order(updated_at: :desc)
  end

  def show
    @messages = @conversation.messages
                             .includes(:sender, attachments: [:file_blob])
                             .order(created_at: :asc)
  end

  def reply
    if params[:content].to_s.strip.blank?
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_support_ticket_path(@conversation), alert: 'Message content is required'
      # rubocop:enable Rails/I18nLocaleTexts
      return
    end

    sender = support_sender
    unless sender
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_support_ticket_path(@conversation), alert: 'No admin user found in Support HQ account'
      # rubocop:enable Rails/I18nLocaleTexts
      return
    end

    message_params = ActionController::Parameters.new(
      content: params[:content],
      message_type: 'outgoing'
    )
    Messages::MessageBuilder.new(sender, @conversation, message_params).perform
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_support_ticket_path(@conversation), notice: 'Reply sent'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  def set_support_context
    @support_account = support_hq_account
    unless @support_account
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_settings_path, alert: 'Support HQ account is not configured'
      # rubocop:enable Rails/I18nLocaleTexts
      return
    end

    @support_inbox = support_hq_inbox(@support_account)
    return if @support_inbox

    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_settings_path, alert: 'Support HQ inbox is not provisioned'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def set_conversation
    @conversation = support_conversations.find(params[:id])
  end

  def support_hq_account
    account_id = GlobalConfig.get_value('SUPPORT_HQ_ACCOUNT_ID')
    return if account_id.blank?

    Account.find_by(id: account_id.to_i)
  end

  def support_hq_inbox(account)
    inbox_name = GlobalConfig.get_value('SUPPORT_HQ_INBOX_NAME').presence || 'Support'
    account.inboxes.where('lower(name) = ?', inbox_name.downcase).first
  end

  def support_conversations
    @support_account.conversations.where(inbox_id: @support_inbox.id)
  end

  def support_sender
    @support_account.administrators.first
  end
end
