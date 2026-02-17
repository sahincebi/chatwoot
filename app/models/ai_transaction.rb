class AiTransaction < ApplicationRecord
  belongs_to :account

  enum :kind, { topup: 0, debit: 1, refund: 2, adjustment: 3 }

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :provider_ref, uniqueness: { scope: [:account_id, :provider] }, allow_blank: true, if: :paytr_provider?

  private

  def paytr_provider?
    provider == 'paytr'
  end
end
