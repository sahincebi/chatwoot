class Api::V1::Accounts::SupportTicketsController < Api::V1::Accounts::BaseController
  before_action :set_support_ticket, only: [:show, :messages]

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
          created_at: ticket.created_at,
          unread: ticket.unread_for_requester?(Current.user)
        }
      end
    }
  end

  def show
    mark_requester_read(@support_ticket)
    render json: ticket_payload(@support_ticket)
  end

  def messages
    message = @support_ticket.support_ticket_messages.create!(
      sender: Current.user,
      sender_role: 'requester',
      body: params[:body].to_s.strip,
      files: Array(params[:attachments]).compact
    )
    mark_requester_read(@support_ticket)

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
      unread: ticket.unread_for_requester?(Current.user),
      requester: {
        id: ticket.requester_id,
        name: ticket.requester.name,
        email: ticket.requester.email
      },
      messages: ticket.support_ticket_messages.order(created_at: :asc)
                 .map { |message| message_payload(ticket, message) }
    }
  end

  def message_payload(ticket, message)
    sender_is_support = if message.sender_role.present?
                          message.sender_role == 'support'
                        else
                          message.sender_id != ticket.requester_id
                        end
    {
      id: message.id,
      body: message.body,
      sender_id: message.sender_id,
      sender_name: message.sender&.name || message.sender&.email,
      sender_is_support: sender_is_support,
      sender_role: message.sender_role,
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

  def mark_requester_read(ticket)
    return unless ticket.requester_id == Current.user.id

    ticket.update_column(:requester_last_read_at, Time.zone.now)
  end
end
