# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversation, type: :model do
  describe 'AI assignee auto binding' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

    it 'provisions and assigns ai agent on first conversation when account has no ai_agent_user_id' do
      expect(account.ai_agent_user_id).to be_nil

      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        assignee: nil
      )

      account.reload
      expect(account.ai_agent_user_id).to be_present
      expect(conversation.assignee_id).to eq(account.ai_agent_user_id)
      expect(account.ai_agent).to be_present
      expect(account.ai_agent.is_ai_agent?).to be(true)
    end

    it 'uses existing ai agent without re-provisioning when ai_agent_user_id already exists' do
      ai_user = create(:user, account: account, role: :agent, is_ai_agent: true)
      account.update!(ai_agent_user_id: ai_user.id)

      expect(Account::ProvisionAiAgentService).not_to receive(:new)
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        assignee: nil
      )

      expect(conversation.assignee_id).to eq(ai_user.id)
    end
  end
end
