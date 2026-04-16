class Ai::OpenaiProjectProvisionJob < ApplicationJob
  queue_as :default

  retry_on Ai::OpenaiAdminClient::Error, wait: :polynomially_longer, attempts: 10
  discard_on Ai::OpenaiAdminClient::MissingKeyError, ActiveRecord::RecordNotFound

  def perform(account_id)
    account = Account.find(account_id)
    return if account.openai_project_id.present?

    account.openai_project_provisioning!

    begin
      response = Ai::OpenaiAdminClient.new.create_project(name: "chatwoot_account_#{account.id}")
    rescue Ai::OpenaiAdminClient::Error => e
      account.update(
        openai_project_last_error: e.message,
        openai_project_status: :failed
      )
      raise
    end

    account.update!(
      openai_project_id: response['id'],
      openai_project_status: :active,
      openai_project_created_at: Time.current,
      openai_project_last_error: nil
    )
  end
end
