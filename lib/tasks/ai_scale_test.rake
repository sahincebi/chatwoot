namespace :ai do
  namespace :scale_test do
    desc 'Prepare synthetic accounts for AI scale testing (default TOTAL=100)'
    task prepare: :environment do
      total = ENV.fetch('TOTAL', '100').to_i
      prefix = ENV.fetch('PREFIX', 'AI Scale Test')
      prompt_id = ENV['PROMPT_ID'].presence
      prompt_version = ENV.fetch('PROMPT_VERSION', '1').to_i

      prepared = 0
      total.times do |index|
        account_name = "#{prefix} #{index + 1}"
        account = Account.find_or_create_by!(name: account_name)
        ensure_ai_agent(account)

        updates = {
          ai_enabled: true,
          ai_prompt_version: prompt_version,
          ai_tool_policy: account.ai_tool_policy_with_defaults.merge(
            'enabled' => true,
            'allowed_tools' => {
              'calendar' => true,
              'conversation' => true,
              'demo' => true,
              'email' => true,
              'crm' => true
            }
          )
        }
        updates[:ai_prompt_id] = prompt_id if prompt_id
        account.update!(updates)

        wallet = AiWallet.find_or_create_by!(account_id: account.id)
        wallet.update!(
          balance_cents: [wallet.balance_cents.to_i, 10_000].max,
          currency: 'USD',
          status: :active
        )

        ensure_inbox_and_membership(account)
        prepared += 1
      end

      puts({ event: 'ai_scale_prepare_done', prepared: prepared, prefix: prefix }.inspect)
    end

    desc 'Enqueue incoming messages for prepared synthetic accounts (default PER_ACCOUNT=1)'
    task enqueue_messages: :environment do
      prefix = ENV.fetch('PREFIX', 'AI Scale Test')
      per_account = ENV.fetch('PER_ACCOUNT', '1').to_i
      enqueue_mode = ENV.fetch('ENQUEUE_MODE', 'async')
      timestamp = Time.current.to_i

      accounts = Account.where('name LIKE ?', "#{prefix}%").order(:id)
      enqueued = 0

      accounts.find_each do |account|
        inbox = ensure_inbox_and_membership(account)
        contact = account.contacts.find_or_create_by!(identifier: "ai-scale-contact-#{account.id}") do |record|
          record.name = "AI Scale Contact #{account.id}"
        end
        contact_inbox = ContactInbox.find_or_create_by!(contact_id: contact.id, inbox_id: inbox.id) do |record|
          record.source_id = "ai-scale-source-#{account.id}-#{SecureRandom.hex(4)}"
        end

        per_account.times do |idx|
          conversation = contact_inbox.conversations.create!(
            account_id: account.id,
            inbox_id: inbox.id,
            contact_id: contact.id,
            assignee_id: account.ai_agent_user_id
          )
          incoming = conversation.messages.create!(
            account_id: account.id,
            inbox_id: inbox.id,
            sender: contact,
            message_type: :incoming,
            private: false,
            content: "Scale test message ##{idx + 1} @ #{timestamp}"
          )

          if enqueue_mode == 'inline'
            Ai::RespondToMessageJob.perform_now(incoming.id)
          else
            Ai::RespondToMessageJob.perform_later(incoming.id)
          end
          enqueued += 1
        end
      end

      puts({ event: 'ai_scale_enqueue_done', accounts: accounts.count, enqueued: enqueued, mode: enqueue_mode }.inspect)
    end

    desc 'Report AI load-test KPIs for prepared accounts'
    task report: :environment do
      prefix = ENV.fetch('PREFIX', 'AI Scale Test')
      accounts = Account.where('name LIKE ?', "#{prefix}%")
      account_ids = accounts.select(:id)

      usage = AiUsageLog.where(account_id: account_ids)
      topup = AiTransaction.where(account_id: account_ids, kind: :topup).sum(:amount_cents)
      debit = AiTransaction.where(account_id: account_ids, kind: :debit).sum(:amount_cents)

      puts(
        {
          event: 'ai_scale_report',
          accounts: accounts.count,
          wallets: AiWallet.where(account_id: account_ids).count,
          usage_logs: usage.count,
          total_tokens: usage.sum(:total_tokens),
          provider_cost_cents: usage.sum(:provider_cost_cents),
          billed_cost_cents: usage.sum(:billed_cost_cents),
          total_topup_cents: topup,
          total_debit_cents: debit
        }.inspect
      )
    end

    desc 'Cleanup synthetic load-test accounts'
    task cleanup: :environment do
      prefix = ENV.fetch('PREFIX', 'AI Scale Test')
      accounts = Account.where('name LIKE ?', "#{prefix}%")
      count = accounts.count
      accounts.find_each(&:destroy!)
      puts({ event: 'ai_scale_cleanup_done', removed_accounts: count, prefix: prefix }.inspect)
    end

    def ensure_inbox_and_membership(account)
      inbox = account.inboxes.first
      return inbox if inbox

      channel = Channel::Api.create!(account_id: account.id)
      inbox = Inbox.create!(
        account_id: account.id,
        channel: channel,
        name: 'AI Scale Inbox',
        timezone: 'UTC'
      )

      if account.ai_agent_user_id.present?
        membership = InboxMember.find_or_initialize_by(inbox_id: inbox.id, user_id: account.ai_agent_user_id)
        membership.save! if membership.new_record? || membership.changed?
      end

      inbox
    end

    def ensure_ai_agent(account)
      Account::ProvisionAiAgentService.new(account: account).call
    rescue ActiveRecord::RecordNotUnique
      bind_existing_ai_agent(account)
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record&.errors&.of_kind?(:email, :taken)

      bind_existing_ai_agent(account)
    end

    def bind_existing_ai_agent(account)
      email = "ai-agent+account-#{account.id}@local.ai"
      user = User.find_by(email: email)
      raise unless user

      user.update_column(:is_ai_agent, true) unless user.is_ai_agent?
      account_user = AccountUser.find_or_initialize_by(account_id: account.id, user_id: user.id)
      account_user.role ||= :agent
      account_user.save! if account_user.new_record? || account_user.changed?
      account.update_column(:ai_agent_user_id, user.id)
      account.inboxes.find_each do |inbox|
        membership = InboxMember.find_or_initialize_by(inbox_id: inbox.id, user_id: user.id)
        membership.save! if membership.new_record? || membership.changed?
      end
      user
    end
  end
end
