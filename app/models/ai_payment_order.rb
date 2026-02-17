class AiPaymentOrder < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true

  enum :status, { pending: 0, paid: 1, failed: 2 }

  validates :provider, presence: true
  validates :merchant_oid, presence: true, uniqueness: true
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :payment_amount_cents, numericality: { greater_than: 0 }
end
