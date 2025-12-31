class SupportTicketMessage < ApplicationRecord
  belongs_to :support_ticket, inverse_of: :support_ticket_messages
  belongs_to :sender, polymorphic: true
  has_many_attached :files

  validates :sender_type, :sender_id, presence: true
  validate :body_or_files

  before_validation :assign_sender_role, on: :create
  after_create_commit :touch_ticket_activity

  private

  def body_or_files
    return if body.present? || files.attached?

    errors.add(:body, 'must be present when no files are attached')
  end

  def touch_ticket_activity
    support_sender_type = sender_role.presence || (sender_id == support_ticket.requester_id ? 'requester' : 'support')
    support_ticket.update_columns(
      last_activity_at: created_at,
      last_message_at: created_at,
      last_message_sender_type: support_sender_type
    )
  end

  def assign_sender_role
    return if sender_role.present? || support_ticket.blank?

    self.sender_role = sender_id == support_ticket.requester_id ? 'requester' : 'support'
  end
end
