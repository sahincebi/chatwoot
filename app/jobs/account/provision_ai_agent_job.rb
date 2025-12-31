class Account::ProvisionAiAgentJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account

    Account::ProvisionAiAgentService.new(account: account).call
  end
end
