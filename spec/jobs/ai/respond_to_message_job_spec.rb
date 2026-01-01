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
      ai_agent_user_id: ai_user.id,
      ai_tool_policy: {
        'enabled' => false,
        'allowed_tools' => {},
        'limits' => { 'max_tools_per_turn' => 3, 'max_total_steps' => 6 }
      }
    )
    wallet = AiWallet.find_or_create_by!(account: account)
    wallet.update!(balance_cents: 1000, currency: 'USD', status: :active)
  end

  it 'dedupes usage, debit, and outgoing message for the same message id' do
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

  it 'skips tool loop when policy is disabled' do
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(
        status: 200,
        body: {
          'id' => 'resp_tool_disabled',
          'output' => [
            {
              'type' => 'tool_call',
              'id' => 'call_1',
              'name' => 'calendar_query_availability',
              'arguments' => { start_time: '2025-01-01T10:00:00Z' }.to_json
            }
          ],
          'output_text' => 'ok',
          'model' => 'gpt-test',
          'usage' => { 'input_tokens' => 1, 'output_tokens' => 1, 'total_tokens' => 2 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    expect(Ai::Tools::CalendarQueryAvailability).not_to receive(:call)
    with_modified_env('OPENAI_API_KEY' => 'test') do
      described_class.perform_now(message.id)
    end

    outgoing = Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false)
    expect(outgoing.count).to eq(1)
  end

  it 'runs a tool loop and returns final text' do
    account.update!(
      ai_tool_policy: {
        'enabled' => true,
        'allowed_tools' => { 'calendar_query_availability' => true },
        'limits' => { 'max_tools_per_turn' => 3, 'max_total_steps' => 3 }
      }
    )
    account.ai_integrations.create!(
      provider: 'google_calendar',
      enabled: true,
      refresh_token: 'refresh-token',
      settings: {}
    )

    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(
        {
          status: 200,
          body: {
            'id' => 'resp_tool_1',
            'output' => [
              {
                'type' => 'tool_call',
                'id' => 'call_1',
                'name' => 'calendar_query_availability',
                'arguments' => {
                  start_time: '2025-01-01T10:00:00Z',
                  end_time: '2025-01-01T11:00:00Z',
                  timezone: 'Europe/Istanbul'
                }.to_json
              }
            ],
            'model' => 'gpt-test',
            'usage' => { 'input_tokens' => 10, 'output_tokens' => 0, 'total_tokens' => 10 }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        },
        {
          status: 200,
          body: {
            'id' => 'resp_tool_final',
            'output_text' => 'final answer',
            'model' => 'gpt-test',
            'usage' => { 'input_tokens' => 5, 'output_tokens' => 5, 'total_tokens' => 10 }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      )

    expect(Ai::Tools::CalendarQueryAvailability).to receive(:call).once.and_call_original
    with_modified_env('OPENAI_API_KEY' => 'test') do
      described_class.perform_now(message.id)
    end

    outgoing = Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false)
    expect(outgoing.count).to eq(1)
    expect(outgoing.last.content).to include('final answer')
  end
end
