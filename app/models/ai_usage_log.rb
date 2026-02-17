class AiUsageLog < ApplicationRecord
  belongs_to :account

  validates :input_tokens, :output_tokens, :total_tokens, numericality: { greater_than_or_equal_to: 0 }
  validates :cost_cents, :provider_cost_cents, :billed_cost_cents, numericality: { greater_than_or_equal_to: 0 }
end
