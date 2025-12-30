account = Account.first
raise 'No account found' unless account

requester = account.users.first
raise 'No requester user found' unless requester

support_user = if User.column_names.include?('super_admin')
                 User.where(super_admin: true).where.not(id: requester.id).first
               else
                 User.where.not(id: requester.id).first
               end
raise 'No support user found' unless support_user

ticket = SupportTicketBuilder.new(
  account: account,
  requester: requester,
  subject: 'Support smoke test',
  category: 'technical',
  priority: 'normal',
  description: 'Requester message from smoke test'
).perform

SupportTicketMessage.create!(
  support_ticket: ticket,
  sender: support_user,
  sender_role: 'support',
  body: 'Support reply from smoke test'
)

payload = Api::V1::Accounts::SupportTicketsController.new.send(:ticket_payload, ticket)
message = payload[:messages].last

puts "ticket_id=#{ticket.id}"
puts "messages=#{ticket.support_ticket_messages.pluck(:id, :sender_id, :sender_role).inspect}"
puts "api_message_payload=#{message.slice(:id, :sender_role, :sender_is_support).inspect}"
