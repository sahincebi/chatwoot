require 'administrate/base_dashboard'

class SupportTicketMessageDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    support_ticket: Field::BelongsTo,
    sender: Field::Polymorphic,
    files: Field::ActiveStorage,
    id: Field::Number,
    body: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    support_ticket
    sender
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    support_ticket
    sender
    body
    files
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    support_ticket
    sender
    body
    files
  ].freeze
end
