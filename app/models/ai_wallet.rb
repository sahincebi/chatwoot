class AiWallet < ApplicationRecord
  belongs_to :account

  enum :status, { active: 0, blocked: 1 }

  validates :balance_cents, numericality: { greater_than_or_equal_to: 0 }
end
