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
        status: 'open'
      )

      message = ticket.messages.create!(
        sender: @requester,
        body: @description,
        files: @attachments
      )

      [ticket, message]
    end
  end
end
