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

  desc 'Enqueue OpenAI project provisioning for accounts missing a project_id'
  task backfill_openai_projects: :environment do
    Account.where(openai_project_id: nil).in_batches(of: 1000) do |batch|
      jobs = batch.pluck(:id).map { |id| Ai::OpenaiProjectProvisionJob.new(id) }
      ActiveJob.perform_all_later(jobs)
    end
  end
end
