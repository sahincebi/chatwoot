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

  private

  def set_last_activity_at
    self.last_activity_at ||= Time.current
  end
end
