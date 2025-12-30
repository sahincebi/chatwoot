class SuperAdmin::SupportTicketsController < SuperAdmin::ApplicationController
  before_action :set_support_ticket, only: [:show, :reply, :update]

  def index
    @tickets = SupportTicket.includes(:account, :requester).order(last_activity_at: :desc)
  end

  def show
    @messages = @ticket.support_ticket_messages
                       .includes(:sender, files_attachments: [:blob])
                       .order(created_at: :asc)
    mark_admin_read(@ticket)
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
      sender_role: 'support',
      body: body
    )
    @ticket.update!(last_activity_at: Time.zone.now, admin_last_read_at: Time.zone.now)

    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_support_ticket_path(@ticket), notice: 'Reply sent'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def update
    status = params.require(:support_ticket).permit(:status)[:status]
    if SupportTicket.statuses.key?(status)
      @ticket.update!(status: status)
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_support_ticket_path(@ticket), notice: 'Status updated'
      # rubocop:enable Rails/I18nLocaleTexts
    else
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_support_ticket_path(@ticket), alert: 'Invalid status'
      # rubocop:enable Rails/I18nLocaleTexts
    end
  end

  private

  def set_support_ticket
    @ticket = SupportTicket
              .includes(:account, :requester, support_ticket_messages: :sender)
              .find(params[:id])
  end

  def mark_admin_read(ticket)
    ticket.update_column(:admin_last_read_at, Time.zone.now)
  end
end
