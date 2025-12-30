class BackfillSupportTicketSenderRoles < ActiveRecord::Migration[7.1]
  def up
    return unless column_exists?(:support_ticket_messages, :sender_role)

    SupportTicketMessage.includes(:support_ticket).where(sender_role: nil).find_each do |message|
      role = message.sender_id == message.support_ticket.requester_id ? 'requester' : 'support'
      message.update_columns(sender_role: role)
    end

    SupportTicket.find_each do |ticket|
      last_message = ticket.support_ticket_messages.order(created_at: :desc).first
      next unless last_message

      sender_role = last_message.sender_role.presence ||
                    (last_message.sender_id == ticket.requester_id ? 'requester' : 'support')
      ticket.update_columns(
        last_message_at: last_message.created_at,
        last_message_sender_type: sender_role
      )
    end
  end

  def down
    # no-op
  end
end
