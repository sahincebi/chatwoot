class SupportTicket < ApplicationRecord
  belongs_to :account
  belongs_to :requester, class_name: 'User'
  has_many :support_ticket_messages,
           class_name: 'SupportTicketMessage',
           dependent: :destroy,
           inverse_of: :support_ticket

  enum status: { open: 0, pending: 1, solved: 2, closed: 3 }
  enum priority: { low: 0, normal: 1, high: 2, urgent: 3 }

  validates :subject, presence: true

  before_validation :set_last_activity_at

  def unread_for_requester?(user)
    return false unless user && requester_id == user.id
    ensure_last_message_tracking!
    return false unless last_message_at.present? && last_message_sender_type == 'support'

    requester_last_read_at.blank? || requester_last_read_at < last_message_at
  end

  def unread_for_admin?
    ensure_last_message_tracking!
    return false unless last_message_at.present? && last_message_sender_type == 'requester'

    admin_last_read_at.blank? || admin_last_read_at < last_message_at
  end

  private

  def set_last_activity_at
    self.last_activity_at ||= Time.current
  end

  def ensure_last_message_tracking!
    last_message = support_ticket_messages.order(created_at: :desc).first
    return unless last_message

    support_sender_type = last_message.sender_role.presence ||
                          (last_message.sender_id == requester_id ? 'requester' : 'support')
    needs_update = last_message_at != last_message.created_at || last_message_sender_type != support_sender_type

    update_columns(last_message_at: last_message.created_at, last_message_sender_type: support_sender_type) if needs_update
  end
end
