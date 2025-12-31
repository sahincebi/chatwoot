class AiTransaction < ApplicationRecord
  belongs_to :account

  enum :kind, { topup: 0, debit: 1, refund: 2, adjustment: 3 }

  validates :amount_cents, numericality: { greater_than: 0 }
end
