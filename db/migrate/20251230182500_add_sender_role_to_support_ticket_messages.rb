class AddSenderRoleToSupportTicketMessages < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:support_ticket_messages, :sender_role)

    add_column :support_ticket_messages, :sender_role, :string
  end
end
