require 'net/http'

class Ai::RespondToMessageJob < ApplicationJob
  queue_as :default

  SKIP_REASONS = {
    already_processed: 'already_processed',
    ai_agent_missing: 'ai_agent_missing',
    not_assigned_to_ai: 'not_assigned_to_ai',
    ai_disabled: 'ai_disabled',
    missing_prompt: 'missing_prompt',
    missing_wallet: 'missing_wallet',
    insufficient_balance: 'insufficient_balance',
    ai_response_empty: 'ai_response_empty',
    tool_policy_disabled: 'tool_policy_disabled'
  }.freeze

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message
    return unless message.incoming? && !message.private?

    conversation = message.conversation
    account = Account.find_by(id: message.account_id)
    return unless conversation && account

    account = Account.find(account.id)
    conversation = Conversation.find(conversation.id)

    ai_user = account.ai_agent

    log_event(
      event: 'start',
      account: account,
      conversation: conversation,
      message: message,
      prompt_id: account.ai_prompt_id,
      prompt_version: account.ai_prompt_version
    )
    if AiUsageLog.exists?(account_id: account.id, message_id: message.id)
      return log_skip(account, conversation, message, SKIP_REASONS[:already_processed])
    end
    return log_skip(account, conversation, message, SKIP_REASONS[:ai_agent_missing]) unless ai_user&.is_ai_agent?
    return log_skip(account, conversation, message, SKIP_REASONS[:not_assigned_to_ai]) unless conversation.assignee_id == ai_user.id
    return log_skip(account, conversation, message, SKIP_REASONS[:ai_disabled]) unless account.ai_enabled?
    return log_skip(account, conversation, message, SKIP_REASONS[:missing_prompt]) if account.ai_prompt_id.blank?

    wallet = account.ai_wallet
    return log_skip(account, conversation, message, SKIP_REASONS[:missing_wallet]) unless wallet
    return log_skip(account, conversation, message, SKIP_REASONS[:insufficient_balance], balance_before: wallet.balance_cents) unless wallet.balance_cents.to_i.positive?

    response_payload = fetch_ai_response(account, conversation, message)
    return log_skip(account, conversation, message, SKIP_REASONS[:ai_response_empty]) unless response_payload[:text].present?

    usage = response_payload[:usage] || {}
    input_tokens = usage['input_tokens'].to_i
    output_tokens = usage['output_tokens'].to_i
    total_tokens = usage['total_tokens'].to_i
    total_tokens = input_tokens + output_tokens if total_tokens.zero?
    cost_cents = calculate_cost_cents(input_tokens, output_tokens)

    balance_after = nil
    balance_before = nil
    response_id = response_payload[:response_id]
    wallet.with_lock do
      wallet.reload
      balance_before = wallet.balance_cents
      if wallet.balance_cents.to_i < cost_cents
        return log_skip(account, conversation, message, SKIP_REASONS[:insufficient_balance], balance_before: wallet.balance_cents)
      end

      if cost_cents.positive?
        wallet.update!(balance_cents: wallet.balance_cents - cost_cents)
        AiTransaction.create!(
          account: account,
          kind: :debit,
          amount_cents: cost_cents,
          currency: wallet.currency,
          provider: 'openai',
          provider_ref: response_id,
          meta: { prompt_id: account.ai_prompt_id, prompt_version: account.ai_prompt_version }
        )
      end

      AiUsageLog.create!(
        account: account,
        conversation_id: conversation.id,
        message_id: message.id,
        prompt_id: account.ai_prompt_id,
        prompt_version: account.ai_prompt_version,
        model: response_payload[:model],
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: total_tokens,
        cost_cents: cost_cents,
        currency: wallet.currency,
        meta: {
          provider: 'openai',
          response_id: response_payload[:response_id],
          raw_response: response_payload[:raw_response]
        }
      )

      balance_after = wallet.balance_cents
    end

    normalized_text = normalize_ai_text(response_payload[:text])
    params = ActionController::Parameters.new(
      content: normalized_text,
      message_type: 'outgoing',
      private: false
    )
    Messages::MessageBuilder.new(ai_user, conversation, params).perform

    log_event(
      event: 'success',
      account: account,
      conversation: conversation,
      message: message,
      prompt_id: account.ai_prompt_id,
      prompt_version: account.ai_prompt_version,
      model: response_payload[:model],
      response_id: response_id,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens,
      cost_cents: cost_cents,
      balance_before: balance_before,
      balance_after: balance_after
    )
  end

  private

  def fetch_ai_response(account, conversation, message)
    api_key = ENV['OPENAI_API_KEY']
    return { text: nil } if api_key.blank?

    endpoint = ENV['AI_OPENAI_ENDPOINT'] || ENV['OPENAI_BASE_URL'] || 'https://api.openai.com'
    uri = URI.join(endpoint.chomp('/'), '/v1/responses')

    context_messages = conversation.messages
                                   .where(message_type: [:incoming, :outgoing], private: false)
                                   .order(:created_at)
                                   .last(30)
    context = context_messages.map do |msg|
      label = msg.incoming? ? 'Customer' : 'Agent'
      "#{label}: #{msg.content_for_llm}"
    end.join("\n")

    input_text = <<~TEXT
      Conversation:
      #{context}

      Latest customer message:
      #{message.content_for_llm}
    TEXT

    payload = { input: input_text }
    if ENV['AI_MODEL'].present?
      payload[:model] = ENV['AI_MODEL']
    end
    if account.ai_prompt_id.present?
      prompt_obj = { id: account.ai_prompt_id }
      if account.ai_prompt_version.present?
        prompt_obj[:version] = account.ai_prompt_version.to_s
      end
      payload[:prompt] = prompt_obj
    end
    tool_schemas = Ai::Tools::ToolRegistry.tool_schemas_for(account)
    payload[:tools] = tool_schemas if tool_schemas.any?

    response_payload = call_openai(account, conversation, message, uri, api_key, payload)
    return response_payload unless tool_schemas.any?

    run_tool_loop(account, conversation, message, uri, api_key, response_payload, tool_schemas)
  end

  def extract_text(parsed)
    return parsed['output_text'] if parsed['output_text'].present?

    outputs = parsed['output'] || []
    outputs.each do |output|
      contents = output['content'] || []
      contents.each do |content|
        text = content['text'] || content.dig('text', 'value')
        return text if text.present?
      end
    end

    parsed.dig('choices', 0, 'message', 'content')
  end

  def extract_tool_calls(parsed)
    outputs = parsed['output'] || []
    outputs.filter_map do |output|
      next unless output['type'] == 'tool_call'

      {
        id: output['id'] || output['call_id'],
        name: output['name'],
        arguments: output['arguments']
      }
    end
  end

  def run_tool_loop(account, conversation, message, uri, api_key, response_payload, tool_schemas)
    policy = account.ai_tool_policy_with_defaults
    limits = policy['limits'] || {}
    max_tools_per_turn = limits['max_tools_per_turn'].to_i
    max_total_steps = limits['max_total_steps'].to_i
    max_tools_per_turn = 3 if max_tools_per_turn <= 0
    max_total_steps = 6 if max_total_steps <= 0

    tool_calls = extract_tool_calls(response_payload[:raw_response])
    return response_payload if tool_calls.empty?

    unless account.tool_calling_enabled? && tool_schemas.any?
      log_event(
        event: 'tool_error',
        account: account,
        conversation: conversation,
        message: message,
        prompt_id: account.ai_prompt_id,
        prompt_version: account.ai_prompt_version,
        reason: SKIP_REASONS[:tool_policy_disabled],
        step: 1
      )
      return response_payload
    end

    steps = 0
    while tool_calls.any? && steps < max_total_steps
      steps += 1
      tool_results = []

      tool_calls.first(max_tools_per_turn).each do |tool_call|
        tool_name = tool_call[:name]
        log_event(
          event: 'tool_call',
          account: account,
          conversation: conversation,
          message: message,
          prompt_id: account.ai_prompt_id,
          prompt_version: account.ai_prompt_version,
          tool_name: tool_name,
          step: steps
        )

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = Ai::Tools::ToolRegistry.execute(account: account, tool_call: tool_call)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        if result[:error].present?
          log_event(
            event: 'tool_error',
            account: account,
            conversation: conversation,
            message: message,
            prompt_id: account.ai_prompt_id,
            prompt_version: account.ai_prompt_version,
            tool_name: tool_name,
            step: steps,
            duration_ms: duration_ms,
            reason: result[:error]
          )
        else
          log_event(
            event: 'tool_result',
            account: account,
            conversation: conversation,
            message: message,
            prompt_id: account.ai_prompt_id,
            prompt_version: account.ai_prompt_version,
            tool_name: tool_name,
            step: steps,
            duration_ms: duration_ms
          )
        end

        tool_results << {
          type: 'tool_result',
          tool_call_id: tool_call[:id],
          content: result.to_json
        }
      end

      if tool_calls.size > max_tools_per_turn
        tool_calls.drop(max_tools_per_turn).each do |tool_call|
          tool_name = tool_call[:name]
          log_event(
            event: 'tool_error',
            account: account,
            conversation: conversation,
            message: message,
            prompt_id: account.ai_prompt_id,
            prompt_version: account.ai_prompt_version,
            tool_name: tool_name,
            step: steps,
            reason: 'tool_limit_exceeded'
          )
          tool_results << {
            type: 'tool_result',
            tool_call_id: tool_call[:id],
            content: { error: 'tool_limit_exceeded' }.to_json
          }
        end
      end

      break if tool_results.empty?

      followup_payload = {
        input: tool_results,
        previous_response_id: response_payload[:response_id]
      }
      followup_payload[:model] = ENV['AI_MODEL'] if ENV['AI_MODEL'].present?
      followup_payload[:tools] = tool_schemas if tool_schemas.any?

      response_payload = call_openai(account, conversation, message, uri, api_key, followup_payload)
      tool_calls = extract_tool_calls(response_payload[:raw_response])
    end

    if tool_calls.any?
      log_event(
        event: 'tool_error',
        account: account,
        conversation: conversation,
        message: message,
        prompt_id: account.ai_prompt_id,
        prompt_version: account.ai_prompt_version,
        reason: 'tool_max_steps_exceeded',
        step: steps
      )
    end

    response_payload
  end

  def call_openai(account, conversation, message, uri, api_key, payload)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    request = Net::HTTP::Post.new(uri.request_uri)
    request['Authorization'] = "Bearer #{api_key}"
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json
    response = http.request(request)

    parsed = JSON.parse(response.body) rescue {}
    http_status = response.code.to_i
    parsed['_http_status'] = http_status
    if http_status >= 400
      log_event(
        event: 'error',
        account: account,
        conversation: conversation,
        message: message,
        prompt_id: account.ai_prompt_id,
        prompt_version: account.ai_prompt_version,
        model: parsed['model'],
        response_id: parsed['id'],
        reason: 'openai_error',
        http_status: http_status
      )
      Rails.logger.info("[AI_REPLY] openai_error status=#{response.code} body=#{response.body.to_s.truncate(400)}")
    end
    {
      text: extract_text(parsed),
      usage: parsed['usage'],
      model: parsed['model'],
      response_id: parsed['id'],
      raw_response: parsed,
      http_status: http_status
    }
  end

  def calculate_cost_cents(input_tokens, output_tokens)
    input_rate = ENV.fetch('AI_INPUT_COST_PER_1M', '0').to_f
    output_rate = ENV.fetch('AI_OUTPUT_COST_PER_1M', '0').to_f
    cost = (input_tokens * input_rate + output_tokens * output_rate) / 1_000_000.0
    (cost * 100).round
  end

  def normalize_ai_text(raw_text)
    return raw_text unless raw_text.is_a?(String)

    json_candidate = extract_json_candidate(raw_text)
    return raw_text if json_candidate.blank?

    parsed = JSON.parse(json_candidate)
    extracted = parsed.dig('data', 'message') || parsed['message'] || parsed.dig('data', 'text') || parsed.dig('data', 'content')
    extracted.presence || raw_text
  rescue JSON::ParserError => e
    Rails.logger.info("[AI_REPLY] normalize_error=#{e.class}: #{e.message.to_s.truncate(200)}")
    raw_text
  end

  def extract_json_candidate(raw_text)
    stripped = raw_text.strip
    return stripped if stripped.start_with?('{') && stripped.end_with?('}')

    fenced_match = stripped.match(/```json\s*(\{.*?\})\s*```/m) || stripped.match(/```\s*(\{.*?\})\s*```/m)
    return fenced_match[1] if fenced_match

    start_idx = stripped.index('{')
    end_idx = stripped.rindex('}')
    return nil unless start_idx && end_idx && end_idx > start_idx

    stripped[start_idx..end_idx]
  end

  def log_skip(account, conversation, message, reason, balance_before: nil)
    log_event(
      event: 'skip',
      account: account,
      conversation: conversation,
      message: message,
      prompt_id: account&.ai_prompt_id,
      prompt_version: account&.ai_prompt_version,
      balance_before: balance_before,
      reason: reason
    )
    nil
  end

  def log_event(
    event:,
    account:,
    conversation:,
    message:,
    prompt_id: nil,
    prompt_version: nil,
    model: nil,
    response_id: nil,
    input_tokens: nil,
    output_tokens: nil,
    total_tokens: nil,
    cost_cents: nil,
    balance_before: nil,
    balance_after: nil,
    reason: nil,
    http_status: nil,
    tool_name: nil,
    step: nil,
    duration_ms: nil
  )
    payload = {
      event: event,
      reason: reason,
      account_id: account&.id,
      conversation_id: conversation&.id,
      message_id: message&.id,
      prompt_id: prompt_id,
      prompt_version: prompt_version,
      model: model,
      response_id: response_id,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens,
      cost_cents: cost_cents,
      balance_before: balance_before,
      balance_after: balance_after,
      http_status: http_status,
      tool_name: tool_name,
      step: step,
      duration_ms: duration_ms
    }.compact
    Rails.logger.info("[AI_REPLY] #{payload.to_json}")
  end
end
