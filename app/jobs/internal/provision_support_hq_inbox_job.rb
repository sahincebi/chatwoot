class Internal::ProvisionSupportHqInboxJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil)
    Rails.logger.info('[SupportHqProvision] job=internal_provision_support_hq_inbox status=started')
    inbox = Internal::ProvisionSupportHqInboxService.new.call
    ensure_requester_membership(inbox, user_id) if inbox.present?
  rescue StandardError => e
    Rails.logger.warn("[SupportHqProvision] error=#{e.class}: #{e.message}")
  end

  private

  def ensure_requester_membership(inbox, user_id)
    return if user_id.blank?

    user = User.find_by(id: user_id)
    return unless user

    account = inbox.account
    AccountUser.find_or_create_by!(account_id: account.id, user_id: user.id) do |account_user|
      account_user.role = :administrator
    end
    InboxMember.find_or_create_by!(inbox: inbox, user_id: user.id)
  end
end
