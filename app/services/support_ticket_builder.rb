class SupportTicketBuilder
  def initialize(account:, requester:, subject:, category:, priority:, description:, attachments: [])
    @account = account
    @requester = requester
    @subject = subject
    @category = category
    @priority = priority
    @description = description
    @attachments = Array(attachments).compact
  end

  def perform
    SupportTicket.transaction do
      ticket = SupportTicket.create!(
        account: @account,
        requester: @requester,
        subject: @subject,
        category: @category,
        priority: @priority.presence || 'normal',
        status: 'open',
        requester_last_read_at: Time.zone.now
      )

      ticket.support_ticket_messages.create!(
        sender: @requester,
        sender_role: 'requester',
        body: @description,
        files: @attachments
      )

      ticket.update!(last_activity_at: Time.zone.now)

      ticket
    end
  end
end
