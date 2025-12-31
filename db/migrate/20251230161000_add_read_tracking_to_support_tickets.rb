class AddReadTrackingToSupportTickets < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:support_tickets, :requester_last_read_at)
      add_column :support_tickets, :requester_last_read_at, :datetime
    end

    unless column_exists?(:support_tickets, :admin_last_read_at)
      add_column :support_tickets, :admin_last_read_at, :datetime
    end

    unless column_exists?(:support_tickets, :last_message_at)
      add_column :support_tickets, :last_message_at, :datetime
    end

    unless column_exists?(:support_tickets, :last_message_sender_type)
      add_column :support_tickets, :last_message_sender_type, :string
    end
  end
end
