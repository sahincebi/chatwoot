# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Message, type: :model do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:ai_user) { create(:user, account: account, role: :agent, is_ai_agent: true) }
  let(:human_user) { create(:user, account: account, role: :agent, is_ai_agent: false) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      assignee: ai_user
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    account.update!(
      ai_enabled: true,
      ai_prompt_id: 'pmpt_test',
      ai_prompt_version: 1,
      ai_agent_user_id: ai_user.id
    )
  end

  def create_incoming(text)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      sender: contact,
      message_type: :incoming,
      private: false,
      content: text
    )
  end

  it 'enqueues ai reply only when conversation is assigned to ai agent' do
    with_modified_env('AI_REPLY_DEBOUNCE_SECONDS' => '0') do
      expect do
        create_incoming('msg when ai assigned')
      end.to change { enqueued_jobs.count { |job| job[:job] == Ai::RespondToMessageJob } }.by(1)

      conversation.update!(assignee: human_user)

      expect do
        create_incoming('msg when human assigned')
      end.not_to(change { enqueued_jobs.count { |job| job[:job] == Ai::RespondToMessageJob } })

      conversation.update!(assignee: ai_user)

      expect do
        create_incoming('msg when ai reassigned')
      end.to change { enqueued_jobs.count { |job| job[:job] == Ai::RespondToMessageJob } }.by(1)
    end
  end
end
