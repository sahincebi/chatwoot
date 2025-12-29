class Api::V1::Accounts::SupportTicketsController < Api::V1::Accounts::BaseController
  before_action :set_support_ticket, only: [:show, :create_message]

  def create
    ticket = SupportTicketBuilder.new(
      account: Current.account,
      requester: Current.user,
      subject: params[:subject].to_s.strip,
      category: params[:category],
      priority: params[:priority],
      description: params[:description].to_s,
      attachments: params[:attachments]
    ).perform

    render json: { ticket_id: ticket.id }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def index
    tickets = support_ticket_scope.order(last_activity_at: :desc)
    render json: {
      tickets: tickets.map do |ticket|
        {
          id: ticket.id,
          subject: ticket.subject,
          category: ticket.category,
          priority: ticket.priority,
          status: ticket.status,
          last_activity_at: ticket.last_activity_at,
          created_at: ticket.created_at
        }
      end
    }
  end

  def show
    render json: ticket_payload(@support_ticket)
  end

  def create_message
    message = @support_ticket.support_ticket_messages.create!(
      sender: Current.user,
      body: params[:body].to_s.strip,
      files: Array(params[:attachments]).compact
    )
    @support_ticket.update!(last_activity_at: Time.zone.now)

    render json: { message_id: message.id }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_support_ticket
    @support_ticket = support_ticket_scope.find(params[:id])
  end

  def support_ticket_scope
    scope = Current.account.support_tickets
    return scope if Current.account_user&.administrator?

    scope.where(requester_id: Current.user.id)
  end

  def ticket_payload(ticket)
    {
      id: ticket.id,
      subject: ticket.subject,
      category: ticket.category,
      priority: ticket.priority,
      status: ticket.status,
      last_activity_at: ticket.last_activity_at,
      created_at: ticket.created_at,
      requester: {
        id: ticket.requester_id,
        name: ticket.requester.name,
        email: ticket.requester.email
      },
      messages: ticket.support_ticket_messages.order(created_at: :asc).map { |message| message_payload(message) }
    }
  end

  def message_payload(message)
    {
      id: message.id,
      body: message.body,
      sender_type: message.sender_type,
      sender_id: message.sender_id,
      sender_name: message.sender&.name || message.sender&.email,
      created_at: message.created_at,
      attachments: message.files.map { |file| attachment_payload(file) }
    }
  end

  def attachment_payload(file)
    {
      id: file.id,
      filename: file.filename.to_s,
      url: Rails.application.routes.url_helpers.rails_blob_path(
        file,
        disposition: 'attachment',
        only_path: true
      )
    }
  end
end
