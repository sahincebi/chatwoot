class SupportTicketMessage < ApplicationRecord
  belongs_to :support_ticket, inverse_of: :support_ticket_messages
  belongs_to :sender, polymorphic: true
  has_many_attached :files

  validates :sender_type, :sender_id, presence: true
  validate :body_or_files

  after_create_commit :touch_ticket_activity

  private

  def body_or_files
    return if body.present? || files.attached?

    errors.add(:body, 'must be present when no files are attached')
  end

  def touch_ticket_activity
    support_ticket.update_column(:last_activity_at, created_at)
  end
end
