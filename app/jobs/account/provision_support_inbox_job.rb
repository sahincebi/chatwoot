class Account::ProvisionSupportInboxJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find(account_id)
    Account::ProvisionSupportInboxService.new(account: account).call
  end
end
