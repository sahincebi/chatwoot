hq_id = InstallationConfig.get_value('SUPPORT_HQ_ACCOUNT_ID').to_i
hq_id = 2 if hq_id <= 0

InstallationConfig.set_value('SUPPORT_HQ_ACCOUNT_ID', hq_id)
InstallationConfig.set_value('SUPPORT_HQ_INBOX_NAME', 'Support')
InstallationConfig.set_value('SUPPORT_TICKET_SOURCE', 'internal_support_form')

puts "support_hq_account_id=#{InstallationConfig.get_value('SUPPORT_HQ_ACCOUNT_ID').inspect}"

Internal::ProvisionSupportHqInboxJob.perform_now

account = Account.find(hq_id)
name = InstallationConfig.get_value('SUPPORT_HQ_INBOX_NAME') || 'Support'
inbox = account.inboxes.where('lower(name)=?', name.downcase).first

puts "hq_inbox_id=#{inbox&.id} name=#{inbox&.name}"
