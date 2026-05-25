class AiWallet < ApplicationRecord
  belongs_to :account

  LOW_BALANCE_THRESHOLD_CENTS = 500

  enum :status, { active: 0, blocked: 1 }

  validates :balance_cents, numericality: { greater_than_or_equal_to: 0 }

  def low_balance?
    balance_cents < LOW_BALANCE_THRESHOLD_CENTS
  end
end
