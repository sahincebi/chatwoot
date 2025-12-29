class SuperAdmin::SupportTicketsController < SuperAdmin::ApplicationController
  before_action :set_support_ticket, only: [:show, :reply]

  def index
    @tickets = SupportTicket.includes(:account, :requester).order(last_activity_at: :desc)
  end

  def show
    @messages = @support_ticket.messages
                               .includes(:sender, files_attachments: [:blob])
                               .order(created_at: :asc)
  end

  def reply
    body = params[:body].to_s.strip
    if body.blank?
      # rubocop:disable Rails/I18nLocaleTexts
      redirect_to super_admin_support_ticket_path(@support_ticket), alert: 'Message content is required'
      # rubocop:enable Rails/I18nLocaleTexts
      return
    end

    SupportTicketMessage.create!(
      support_ticket: @support_ticket,
      sender: current_super_admin,
      body: body
    )

    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_support_ticket_path(@support_ticket), notice: 'Reply sent'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  def set_support_ticket
    @support_ticket = SupportTicket.find(params[:id])
  end
end
