require 'rails_helper'

RSpec.describe Ai::RespondToMessageJob do
  let(:account) { create(:account) }
  let(:ai_user) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: ai_user) }
  let(:message) do
    create(
      :message,
      account: account,
      conversation: conversation,
      inbox: inbox,
      message_type: :incoming,
      private: false,
      content: 'hello'
    )
  end

  before do
    ai_user.update!(is_ai_agent: true)
    account.update!(
      ai_enabled: true,
      ai_prompt_id: 'pmpt_test',
      ai_prompt_version: 1,
      ai_agent_user_id: ai_user.id
    )
    AiWallet.create!(account: account, balance_cents: 1000, currency: 'USD', status: :active)

    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(
        status: 200,
        body: {
          'id' => 'resp_1',
          'output_text' => 'ok',
          'model' => 'gpt-test',
          'usage' => {
            'input_tokens' => 1_000_000,
            'output_tokens' => 0,
            'total_tokens' => 1_000_000
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'dedupes usage, debit, and outgoing message for the same message id' do
    with_modified_env(
      'OPENAI_API_KEY' => 'test',
      'AI_INPUT_COST_PER_1M' => '1',
      'AI_OUTPUT_COST_PER_1M' => '0'
    ) do
      described_class.perform_now(message.id)
      described_class.perform_now(message.id)
    end

    expect(AiUsageLog.where(account_id: account.id, message_id: message.id).count).to eq(1)
    expect(AiTransaction.where(account_id: account.id, kind: :debit).count).to eq(1)
    expect(
      Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false).count
    ).to eq(1)
  end
end
