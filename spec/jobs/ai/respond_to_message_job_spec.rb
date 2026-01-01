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
      .with do |req|
        body = JSON.parse(req.body)
        expect(body['model']).to be_present
        true
      end
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
      .with do |req|
        body = JSON.parse(req.body)
        expect(body['model']).to be_present
        true
      end
      .to_return(
        status: 200,
        body: {
          'id' => 'resp_tool_disabled',
          'output' => [
            {
              'type' => 'tool_call',
              'id' => 'call_1',
              'name' => 'check_demo_availability',
              'arguments' => { date: '2025-01-02', tz: 'Europe/Istanbul' }.to_json
            }
          ],
          'output_text' => 'ok',
          'model' => 'gpt-test',
          'usage' => { 'input_tokens' => 1, 'output_tokens' => 1, 'total_tokens' => 2 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    expect(Ai::Tools::CheckDemoAvailability).not_to receive(:call)
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
        'allowed_tools' => { 'demo' => true },
        'limits' => { 'max_tools_per_turn' => 3, 'max_total_steps' => 3 }
      }
    )
    account.ai_integrations.create!(
      provider: 'google_calendar',
      enabled: true,
      refresh_token: 'refresh-token',
      settings: {}
    )

    request_count = 0
    allow(Rails.logger).to receive(:info)
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .with do |req|
        request_count += 1
        body = JSON.parse(req.body)
        expect(body['model']).to be_present
        expect(body).not_to have_key('tools')
        if request_count == 1
          expect(body.dig('prompt', 'id')).to eq('pmpt_test')
          expect(body.dig('prompt', 'version')).to eq('1')
        else
          expect(body['previous_response_id']).to be_present
          expect(body['input']).to be_an(Array)
          tool_item = body['input'].first
          output = tool_item['output'] || tool_item['content']
          expect { JSON.parse(output) }.not_to raise_error
        end
        true
      end
      .to_return(
        {
          status: 200,
          body: {
            'id' => 'resp_tool_1',
            'output' => [
              {
                'type' => 'tool_call',
                'id' => 'call_1',
                'name' => 'check_demo_availability',
                'arguments' => {
                  date: (Time.find_zone('Europe/Istanbul').today + 1).strftime('%F'),
                  tz: 'Europe/Istanbul'
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

    expect(Ai::Tools::CheckDemoAvailability).to receive(:call).once.and_call_original
    with_modified_env('OPENAI_API_KEY' => 'test') do
      described_class.perform_now(message.id)
    end

    outgoing = Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false)
    expect(outgoing.count).to eq(1)
    expect(outgoing.last.content).to include('final answer')
    expect(Rails.logger).to have_received(:info).with(include('"phase":"initial"')).at_least(:once)
    expect(Rails.logger).to have_received(:info).with(include('"phase":"followup"')).at_least(:once)
  end

  it 'returns early on openai 400 without replying' do
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .with do |req|
        body = JSON.parse(req.body)
        expect(body['model']).to be_present
        true
      end
      .to_return(
        status: 400,
        body: { error: { message: "Missing required parameter: 'prompt.id'." } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    allow(Rails.logger).to receive(:info)
    with_modified_env('OPENAI_API_KEY' => 'test') do
      described_class.perform_now(message.id)
    end

    expect(
      Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false).count
    ).to eq(0)
    expect(AiUsageLog.where(account_id: account.id, message_id: message.id)).to be_empty
    expect(Rails.logger).to have_received(:info).with(include("openai_error status=400 message=Missing required parameter"))
  end

  it 'handles function_call only responses and returns final text' do
    account.update!(
      ai_tool_policy: {
        'enabled' => true,
        'allowed_tools' => { 'demo' => true },
        'limits' => { 'max_tools_per_turn' => 3, 'max_total_steps' => 3 }
      }
    )
    account.ai_integrations.create!(
      provider: 'google_calendar',
      enabled: true,
      refresh_token: 'refresh-token',
      settings: {}
    )

    request_count = 0
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .with do |req|
        request_count += 1
        body = JSON.parse(req.body)
        expect(body['model']).to be_present
        expect(body).not_to have_key('tools')
        if request_count == 2
          expect(body['previous_response_id']).to be_present
          expect(body['input']).to be_an(Array)
        end
        true
      end
      .to_return(
        {
          status: 200,
          body: {
            'id' => 'resp_fc_1',
            'output' => [
              {
                'type' => 'function_call',
                'call_id' => 'call_1',
                'name' => 'check_demo_availability',
                'arguments' => {
                  date: (Time.find_zone('Europe/Istanbul').today + 1).strftime('%F'),
                  tz: 'Europe/Istanbul'
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
            'id' => 'resp_fc_final',
            'output_text' => 'final from function_call',
            'model' => 'gpt-test',
            'usage' => { 'input_tokens' => 5, 'output_tokens' => 5, 'total_tokens' => 10 }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      )

    expect(Ai::Tools::CheckDemoAvailability).to receive(:call).once.and_call_original
    with_modified_env('OPENAI_API_KEY' => 'test') do
      described_class.perform_now(message.id)
    end

    outgoing = Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false)
    expect(outgoing.count).to eq(1)
    expect(outgoing.last.content).to include('final from function_call')
  end

  it 'normalizes structured JSON output to plain text and stores raw payload' do
    raw_json = {
      'action' => 'chat.reply',
      'state' => 'collect',
      'messages' => [
        { 'type' => 'text', 'text' => 'Merhaba' },
        { 'type' => 'text', 'text' => 'Nasil yardim edebilirim?' }
      ]
    }.to_json

    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(
        status: 200,
        body: {
          'id' => 'resp_json',
          'output_text' => raw_json,
          'model' => 'gpt-test',
          'usage' => { 'input_tokens' => 1, 'output_tokens' => 1, 'total_tokens' => 2 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    allow(Rails.logger).to receive(:info)
    with_modified_env('OPENAI_API_KEY' => 'test') do
      described_class.perform_now(message.id)
    end

    outgoing = Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false).last
    expect(outgoing.content).to eq('Merhaba')
    expect(outgoing.content_attributes['ai_raw']).to eq(raw_json)
    expect(outgoing.content_attributes['ai_action']).to eq('chat.reply')
    expect(outgoing.content_attributes['ai_state']).to eq('collect')
    expect(Rails.logger).to have_received(:info).with(include('"event":"normalized_reply"')).at_least(:once)
  end

  it 'normalizes meta message output to plain text' do
    raw_json = {
      'action' => 'chat.reply',
      'state' => 'scheduled',
      'meta' => { 'message' => 'Randevu olusturuldu.' }
    }.to_json

    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(
        status: 200,
        body: {
          'id' => 'resp_meta',
          'output_text' => raw_json,
          'model' => 'gpt-test',
          'usage' => { 'input_tokens' => 1, 'output_tokens' => 1, 'total_tokens' => 2 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    with_modified_env('OPENAI_API_KEY' => 'test') do
      described_class.perform_now(message.id)
    end

    outgoing = Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false).last
    expect(outgoing.content).to eq('Randevu olusturuldu.')
    expect(outgoing.content_attributes['ai_raw']).to eq(raw_json)
    expect(outgoing.content_attributes['ai_action']).to eq('chat.reply')
    expect(outgoing.content_attributes['ai_state']).to eq('scheduled')
  end

  it 'passes through plain text output and stores raw text' do
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(
        status: 200,
        body: {
          'id' => 'resp_plain',
          'output_text' => 'plain reply',
          'model' => 'gpt-test',
          'usage' => { 'input_tokens' => 1, 'output_tokens' => 1, 'total_tokens' => 2 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    with_modified_env('OPENAI_API_KEY' => 'test') do
      described_class.perform_now(message.id)
    end

    outgoing = Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false).last
    expect(outgoing.content).to eq('plain reply')
    expect(outgoing.content_attributes['ai_raw']).to eq('plain reply')
    expect(outgoing.content_attributes['ai_action']).to be_nil
    expect(outgoing.content_attributes['ai_state']).to be_nil
  end

end
