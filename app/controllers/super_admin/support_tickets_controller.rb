class SuperAdmin::SupportTicketsController < SuperAdmin::ApplicationController
  before_action :set_support_ticket, only: [:show, :reply]

  def index
    @tickets = SupportTicket.includes(:account, :requester).order(last_activity_at: :desc)
  end

  def show
    @messages = @ticket.support_ticket_messages
                       .includes(:sender, files_attachments: [:blob])
                       .order(created_at: :asc)
  end

  def reply
    body = params.require(:message).permit(:body)[:body].to_s.strip
    if body.blank?
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_support_ticket_path(@ticket), alert: 'Message content is required'
      # rubocop:enable Rails/I18nLocaleTexts
      return
    end

    SupportTicketMessage.create!(
      support_ticket: @ticket,
      sender: current_super_admin,
      body: body
    )
    @ticket.update!(last_activity_at: Time.zone.now)

    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_support_ticket_path(@ticket), notice: 'Reply sent'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  def set_support_ticket
    @ticket = SupportTicket
              .includes(:account, :requester, support_ticket_messages: :sender)
              .find(params[:id])
  end
end
