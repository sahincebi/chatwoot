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
  rescue ActiveRecord::RecordNotUnique
    find_existing_user_by_email_with_retry
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record&.errors&.of_kind?(:email, :taken)

    find_existing_user_by_email_with_retry
  end

  def ai_agent_email
    "ai-agent+account-#{account.id}@local.ai"
  end

  def ensure_account_user(user)
    account_user = AccountUser.find_or_initialize_by(account_id: account.id, user_id: user.id)
    account_user.role ||= :agent
    account_user.save! if account_user.new_record? || account_user.changed?
    account_user
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    raise unless e.is_a?(ActiveRecord::RecordNotUnique) || e.record&.errors&.of_kind?(:user_id, :taken)

    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def ensure_inbox_membership(user)
    account.inboxes.find_each do |inbox|
      membership = InboxMember.find_or_initialize_by(inbox_id: inbox.id, user_id: user.id)
      membership.save! if membership.new_record? || membership.changed?
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      raise unless e.is_a?(ActiveRecord::RecordNotUnique) || e.record&.errors&.of_kind?(:user_id, :taken)

      InboxMember.find_by(inbox_id: inbox.id, user_id: user.id)
    end
  end

  def find_existing_user_by_email_with_retry
    3.times do
      user = User.find_by(email: ai_agent_email)
      return mark_ai_agent(user) if user

      sleep(0.05)
    end

    nil
  end

  def mark_ai_agent(user)
    user.update_column(:is_ai_agent, true) unless user.is_ai_agent?
    user
  end
end
