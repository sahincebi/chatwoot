require 'administrate/base_dashboard'

class SupportTicketDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    account: Field::BelongsTo,
    requester: Field::BelongsTo.with_options(class_name: 'User'),
    support_ticket_messages: Field::HasMany.with_options(class_name: 'SupportTicketMessage'),
    id: Field::Number,
    subject: Field::String,
    category: Field::String,
    status: Field::String,
    priority: Field::String,
    last_activity_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    subject
    status
    priority
    last_activity_at
    requester
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    requester
    subject
    category
    status
    priority
    last_activity_at
    created_at
    updated_at
    support_ticket_messages
  ].freeze

  FORM_ATTRIBUTES = %i[
    subject
    category
    status
    priority
  ].freeze

  def display_resource(ticket)
    "##{ticket.id} #{ticket.subject}"
  end
end
