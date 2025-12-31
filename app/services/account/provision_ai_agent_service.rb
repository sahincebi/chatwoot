class Account::ProvisionAiAgentService
  AI_AGENT_NAME = 'AI Temsilci'.freeze

  def initialize(account:)
    @account = account
  end

  def call
    return unless account

    user = find_existing_ai_agent || create_ai_agent
    return unless user

    ensure_account_user(user)
    ensure_inbox_membership(user)
    account.update_column(:ai_agent_user_id, user.id) if account.ai_agent_user_id != user.id
    user
  end

  private

  attr_reader :account

  def find_existing_ai_agent
    user = account.ai_agent_user_id ? User.find_by(id: account.ai_agent_user_id) : account.users.find_by(is_ai_agent: true)
    return unless user

    user.update_column(:is_ai_agent, true) unless user.is_ai_agent?
    user
  end

  def create_ai_agent
    password = "AiAgent!#{SecureRandom.hex(6)}"
    user = User.new(
      name: AI_AGENT_NAME,
      email: ai_agent_email,
      password: password,
      password_confirmation: password,
      is_ai_agent: true
    )
    user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
    user.save!
    user
  end

  def ai_agent_email
    "ai-agent+account-#{account.id}@local.ai"
  end

  def ensure_account_user(user)
    AccountUser.find_or_create_by!(account_id: account.id, user_id: user.id) do |account_user|
      account_user.role = :agent
    end
  end

  def ensure_inbox_membership(user)
    account.inboxes.find_each do |inbox|
      InboxMember.find_or_create_by!(inbox_id: inbox.id, user_id: user.id)
    end
  end
end
