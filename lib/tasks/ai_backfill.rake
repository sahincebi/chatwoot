namespace :ai do
  desc 'Backfill AI wallets and defaults for all accounts'
  task backfill_wallets: :environment do
    Account.find_each do |account|
      AiWallet.find_or_create_by!(account_id: account.id)

      updates = {}
      updates[:ai_enabled] = true if account.ai_enabled.nil?
      updates[:ai_prompt_version] = 1 if account.ai_prompt_version.nil?
      account.update_columns(updates) if updates.any?
    end
  end

  desc 'Backfill AI agents for all accounts'
  task backfill_agents: :environment do
    Account.find_each do |account|
      Account::ProvisionAiAgentService.new(account: account).call
    end
  end
end
