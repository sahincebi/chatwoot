class Internal::ProvisionSupportInboxesJob < ApplicationJob
  queue_as :default

  def perform
    Account.find_each do |account|
      Account::ProvisionSupportInboxService.new(account: account).call
    rescue StandardError => e
      Rails.logger.warn("[SupportInboxProvision] account_id=#{account.id} error=#{e.class}: #{e.message}")
    end
  end
end
