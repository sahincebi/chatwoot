require 'administrate/base_dashboard'

class AiPaymentOrderDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    user: Field::BelongsTo,
    provider: Field::String,
    merchant_oid: Field::String.with_options(searchable: true),
    status: Field::Select.with_options(collection: AiPaymentOrder.statuses.keys),
    amount_cents: Field::Number,
    currency: Field::String,
    payment_amount_cents: Field::Number,
    payment_currency: Field::String,
    vat_rate: Field::Number.with_options(decimals: 4),
    fx_rate: Field::Number.with_options(decimals: 6),
    provider_ref: Field::String,
    paytr_status: Field::String,
    fail_reason_code: Field::String,
    fail_reason_message: Field::Text,
    paid_at: Field::DateTime,
    failed_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    meta: SerializedField,
    raw_callback: SerializedField
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    status
    payment_amount_cents
    payment_currency
    provider
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    user
    provider
    merchant_oid
    status
    amount_cents
    currency
    payment_amount_cents
    payment_currency
    vat_rate
    fx_rate
    provider_ref
    paytr_status
    fail_reason_code
    fail_reason_message
    paid_at
    failed_at
    meta
    raw_callback
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {
    pending: ->(resources) { resources.where(status: :pending) },
    paid: ->(resources) { resources.where(status: :paid) },
    failed: ->(resources) { resources.where(status: :failed) },
    recent: ->(resources) { resources.where('created_at > ?', 7.days.ago) }
  }.freeze

  def display_resource(order)
    "#{order.merchant_oid} (#{order.status})"
  end
end
