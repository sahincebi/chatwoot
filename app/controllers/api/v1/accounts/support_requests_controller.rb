class Api::V1::Accounts::SupportRequestsController < Api::V1::Accounts::BaseController
  def create
    ticket = SupportTicketBuilder.new(
      account: Current.account,
      requester: Current.user,
      subject: params[:subject].to_s.strip,
      category: params[:category],
      priority: params[:priority],
      description: support_description,
      attachments: support_attachments
    ).perform

    render json: { ok: true, ticket_id: ticket.id }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def support_description
    params[:description].presence || params.dig(:message, :content).to_s
  end

  def support_attachments
    params[:attachments] || params.dig(:message, :attachments)
  end
end
