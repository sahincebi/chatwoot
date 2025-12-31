puts "null_serialized_value_count=#{InstallationConfig.unscoped.where(serialized_value: nil).count}"

InstallationConfig.set_value('SUPPORT_HQ_ACCOUNT_ID', 2)
InstallationConfig.set_value('SUPPORT_HQ_INBOX_NAME', 'Support')
InstallationConfig.set_value('SUPPORT_TICKET_SOURCE', 'internal_support_form')

puts "SUPPORT_HQ_ACCOUNT_ID=#{InstallationConfig.get_value('SUPPORT_HQ_ACCOUNT_ID').inspect}"
puts "SUPPORT_HQ_INBOX_NAME=#{InstallationConfig.get_value('SUPPORT_HQ_INBOX_NAME').inspect}"
puts "SUPPORT_TICKET_SOURCE=#{InstallationConfig.get_value('SUPPORT_TICKET_SOURCE').inspect}"

Internal::ProvisionSupportHqInboxJob.perform_now

hq_id = InstallationConfig.get_value('SUPPORT_HQ_ACCOUNT_ID').to_i
account = Account.find(hq_id)
name = InstallationConfig.get_value('SUPPORT_HQ_INBOX_NAME') || 'Support'
inbox = account.inboxes.where('lower(name)=?', name.downcase).first
is_support = inbox&.respond_to?(:is_support) ? inbox.is_support : nil

puts "hq_inbox_id=#{inbox&.id} is_support=#{is_support}"
