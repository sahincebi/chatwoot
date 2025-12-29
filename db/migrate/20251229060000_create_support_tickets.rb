class CreateSupportTickets < ActiveRecord::Migration[7.1]
  def change
    create_table :support_tickets do |t|
      t.references :account, null: false, foreign_key: true
      t.references :requester, null: false, foreign_key: { to_table: :users }
      t.string :subject, null: false
      t.string :category
      t.integer :status, null: false, default: 0
      t.integer :priority, null: false, default: 1
      t.datetime :last_activity_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamps
    end

    add_index :support_tickets, :status
    add_index :support_tickets, :last_activity_at
    add_index :support_tickets, :account_id

    create_table :support_ticket_messages do |t|
      t.references :support_ticket, null: false, foreign_key: true
      t.string :sender_type, null: false
      t.bigint :sender_id, null: false
      t.text :body
      t.timestamps
    end

    add_index :support_ticket_messages, %i[sender_type sender_id]
    add_index :support_ticket_messages, :support_ticket_id
    add_index :support_ticket_messages, %i[support_ticket_id created_at], name: 'index_support_ticket_messages_on_ticket_and_created'
  end
end
