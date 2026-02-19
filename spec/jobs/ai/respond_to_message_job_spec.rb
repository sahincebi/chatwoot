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

  it 'uses dedicated ai_replies queue' do
    expect(described_class.queue_name).to eq('ai_replies')
  end

  it 'skips without calling openai when OPENAI_API_KEY is missing' do
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(
        status: 200,
        body: {
          'id' => 'resp_unused',
          'output_text' => 'ok',
          'model' => 'gpt-test',
          'usage' => { 'input_tokens' => 1, 'output_tokens' => 1, 'total_tokens' => 2 }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    with_modified_env('OPENAI_API_KEY' => nil) do
      described_class.perform_now(message.id)
    end

    expect(a_request(:post, 'https://api.openai.com/v1/responses')).not_to have_been_made
    expect(
      Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false).count
    ).to eq(0)
    expect(AiUsageLog.where(account_id: account.id, message_id: message.id)).to be_empty
  end

  it 'uses the same global OPENAI_API_KEY across multiple accounts while preserving account-specific prompts' do
    second_account = create(:account)
    second_ai_user = create(:user, account: second_account, role: :agent, is_ai_agent: true)
    second_inbox = create(:inbox, account: second_account)
    second_conversation = create(:conversation, account: second_account, inbox: second_inbox, assignee: second_ai_user)
    second_message = create(
      :message,
      account: second_account,
      conversation: second_conversation,
      inbox: second_inbox,
      message_type: :incoming,
      private: false,
      content: 'hello from account 2'
    )
    second_account.update!(
      ai_enabled: true,
      ai_prompt_id: 'pmpt_second',
      ai_prompt_version: 7,
      ai_agent_user_id: second_ai_user.id,
      ai_tool_policy: {
        'enabled' => false,
        'allowed_tools' => {},
        'limits' => { 'max_tools_per_turn' => 3, 'max_total_steps' => 6 }
      }
    )
    second_wallet = AiWallet.find_or_create_by!(account: second_account)
    second_wallet.update!(balance_cents: 1000, currency: 'USD', status: :active)

    captured_requests = []
    request_sequence = 0
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .with do |req|
        body = JSON.parse(req.body)
        captured_requests << {
          authorization: req.headers['Authorization'],
          prompt_id: body.dig('prompt', 'id'),
          prompt_version: body.dig('prompt', 'version')
        }
        true
      end
      .to_return do |_req|
        request_sequence += 1
        {
          status: 200,
          body: {
            'id' => "resp_multi_#{request_sequence}",
            'output_text' => "ok #{request_sequence}",
            'model' => 'gpt-test',
            'usage' => {
              'input_tokens' => 1,
              'output_tokens' => 1,
              'total_tokens' => 2
            }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      end

    with_modified_env('OPENAI_API_KEY' => 'shared-key') do
      described_class.perform_now(message.id)
      described_class.perform_now(second_message.id)
    end

    expect(captured_requests.size).to eq(2)
    expect(captured_requests.map { |r| r[:authorization] }.uniq).to eq(['Bearer shared-key'])
    expect(captured_requests.map { |r| r[:prompt_id] }).to contain_exactly('pmpt_test', 'pmpt_second')
    expect(captured_requests.map { |r| r[:prompt_version] }).to contain_exactly('1', '7')
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

  it 'skips processing when advisory lock is not available' do
    allow_any_instance_of(described_class).to receive(:acquire_processing_lock).and_return(false)

    expect_any_instance_of(described_class).not_to receive(:fetch_ai_response)
    with_modified_env('OPENAI_API_KEY' => 'test') do
      described_class.perform_now(message.id)
    end

    expect(
      Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false).count
    ).to eq(0)
    expect(AiUsageLog.where(account_id: account.id, message_id: message.id)).to be_empty
  end

  it 'skips processing when a newer incoming message exists in the same conversation' do
    message
    create(
      :message,
      account: account,
      conversation: conversation,
      inbox: inbox,
      message_type: :incoming,
      private: false,
      content: 'latest message'
    )

    expect_any_instance_of(described_class).not_to receive(:fetch_ai_response)
    with_modified_env('OPENAI_API_KEY' => 'test') do
      described_class.perform_now(message.id)
    end

    expect(
      Message.where(conversation_id: conversation.id, message_type: :outgoing, sender: ai_user, private: false).count
    ).to eq(0)
    expect(AiUsageLog.where(account_id: account.id, message_id: message.id)).to be_empty
    expect(AiTransaction.where(account_id: account.id, kind: :debit)).to be_empty
  end

  it 'applies cached input token pricing when usage includes cached tokens' do
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(
        status: 200,
        body: {
          'id' => 'resp_cached',
          'output_text' => 'ok',
          'model' => 'gpt-5',
          'usage' => {
            'input_tokens' => 1_000_000,
            'output_tokens' => 0,
            'total_tokens' => 1_000_000,
            'input_tokens_details' => { 'cached_tokens' => 500_000 }
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    allow(InstallationConfig).to receive(:get_value).with('AI_INPUT_COST_PER_1M').and_return(nil)
    allow(InstallationConfig).to receive(:get_value).with('AI_OUTPUT_COST_PER_1M').and_return(nil)
    allow(InstallationConfig).to receive(:get_value).with('AI_CACHED_INPUT_COST_PER_1M').and_return(nil)
    allow(InstallationConfig).to receive(:get_value).with('AI_BILLING_MULTIPLIER').and_return(nil)

    with_modified_env(
      'OPENAI_API_KEY' => 'test',
      'AI_INPUT_COST_PER_1M' => nil,
      'AI_OUTPUT_COST_PER_1M' => nil,
      'AI_CACHED_INPUT_COST_PER_1M' => nil,
      'AI_BILLING_MULTIPLIER' => nil
    ) do
      described_class.perform_now(message.id)
    end

    usage = AiUsageLog.find_by!(account_id: account.id, message_id: message.id)
    # 500k uncached @1.25 + 500k cached @0.125 => $0.6875 => 69 cents
    expect(usage.provider_cost_cents).to eq(69)
    expect(usage.billed_cost_cents).to eq(276)
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
    expect(outgoing.content).to eq("Merhaba\nNasil yardim edebilirim?")
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

  it 'normalizes meta reply output to plain text' do
    raw_json = {
      'action' => 'chat.reply',
      'state' => 'qualify',
      'meta' => { 'reply' => 'Merhaba, size nasil yardimci olabilirim?' }
    }.to_json

    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(
        status: 200,
        body: {
          'id' => 'resp_meta_reply',
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
    expect(outgoing.content).to eq('Merhaba, size nasil yardimci olabilirim?')
    expect(outgoing.content_attributes['ai_raw']).to eq(raw_json)
    expect(outgoing.content_attributes['ai_action']).to eq('chat.reply')
    expect(outgoing.content_attributes['ai_state']).to eq('qualify')
  end

  it 'normalizes response field output to plain text' do
    raw_json = {
      'action' => 'chat.reply',
      'state' => 'qualify',
      'response' => 'Yarin 15:00-16:00 uygundur.'
    }.to_json

    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(
        status: 200,
        body: {
          'id' => 'resp_response',
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
    expect(outgoing.content).to eq('Yarin 15:00-16:00 uygundur.')
    expect(outgoing.content_attributes['ai_raw']).to eq(raw_json)
    expect(outgoing.content_attributes['ai_action']).to eq('chat.reply')
    expect(outgoing.content_attributes['ai_state']).to eq('qualify')
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
