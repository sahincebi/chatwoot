require 'net/http'

class Ai::RespondToMessageJob < ApplicationJob
  queue_as :ai_replies
  MIN_BALANCE_CENTS = 10
  PROCESSING_LOCK_NAMESPACE = 91_001
  OPENAI_RETRYABLE_ERRORS = [
    Net::OpenTimeout,
    Net::ReadTimeout,
    Timeout::Error,
    Errno::ECONNRESET,
    Errno::ETIMEDOUT,
    SocketError,
    OpenSSL::SSL::SSLError
  ].freeze

  retry_on(*OPENAI_RETRYABLE_ERRORS, wait: :exponentially_longer, attempts: 8)

  SKIP_REASONS = {
    already_processed: 'already_processed',
    already_running: 'already_running',
    superseded_message: 'superseded_message',
    ai_agent_missing: 'ai_agent_missing',
    not_assigned_to_ai: 'not_assigned_to_ai',
    ai_disabled: 'ai_disabled',
    missing_prompt: 'missing_prompt',
    missing_wallet: 'missing_wallet',
    insufficient_balance: 'insufficient_balance',
    ai_response_empty: 'ai_response_empty',
    tool_loop_failed: 'tool_loop_failed',
    tool_policy_disabled: 'tool_policy_disabled'
  }.freeze
  CHAT_REPLY_FALLBACK_TEXT = 'Teşekkürler, bilgileri aldım. Kısa süre içinde net teklif paylaşacağım.'.freeze
  MISSING_REPLY_FIELDS = %w[
    messages[].text
    data.message
    meta.reply
    meta.message
    reply
    message
    data.text
    data.content
    data.reply
  ].freeze

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
      prompt_version: account.ai_prompt_version,
      model: ai_model,
      phase: 'initial'
    )
    if AiUsageLog.exists?(account_id: account.id, message_id: message.id)
      return log_skip(account, conversation, message, SKIP_REASONS[:already_processed])
    end
    return log_skip(account, conversation, message, SKIP_REASONS[:ai_agent_missing]) unless ai_user&.is_ai_agent?
    return log_skip(account, conversation, message, SKIP_REASONS[:not_assigned_to_ai]) unless conversation.assignee_id == ai_user.id
    if superseded_by_newer_incoming_message?(conversation, message)
      return log_skip(account, conversation, message, SKIP_REASONS[:superseded_message])
    end
    return log_skip(account, conversation, message, SKIP_REASONS[:ai_disabled]) unless account.ai_enabled?
    return log_skip(account, conversation, message, SKIP_REASONS[:missing_prompt]) if account.ai_prompt_id.blank?

    wallet = account.ai_wallet
    return log_skip(account, conversation, message, SKIP_REASONS[:missing_wallet]) unless wallet
    if wallet.balance_cents.to_i < MIN_BALANCE_CENTS
      return log_skip(account, conversation, message, SKIP_REASONS[:insufficient_balance], balance_before: wallet.balance_cents)
    end

    unless acquire_processing_lock(message.id)
      return log_skip(account, conversation, message, SKIP_REASONS[:already_running])
    end

    begin
      if superseded_by_newer_incoming_message?(conversation, message)
        return log_skip(account, conversation, message, SKIP_REASONS[:superseded_message])
      end

      response_payload = fetch_ai_response(account, conversation, message)
      return if response_payload[:error] == 'openai_error'
      unless response_payload[:text].present?
        reason = response_payload[:output_types].present? ? SKIP_REASONS[:tool_loop_failed] : SKIP_REASONS[:ai_response_empty]
        log_event(
          event: 'error',
          account: account,
          conversation: conversation,
          message: message,
          prompt_id: account.ai_prompt_id,
          prompt_version: account.ai_prompt_version,
          response_id: response_payload[:response_id],
          reason: reason,
          output_types: response_payload[:output_types],
          first_tool_name: response_payload[:first_tool_name]
        )
        return log_skip(account, conversation, message, reason)
      end

      usage = response_payload[:usage] || {}
      input_tokens = usage['input_tokens'].to_i
      output_tokens = usage['output_tokens'].to_i
      total_tokens = usage['total_tokens'].to_i
      total_tokens = input_tokens + output_tokens if total_tokens.zero?
      model_for_pricing = response_payload[:model].presence || ai_model
      pricing_config = Ai::PricingConfig.current(model: model_for_pricing)
      cached_input_tokens, uncached_input_tokens = token_breakdown(input_tokens, usage)
      provider_cost_cents = calculate_provider_cost_cents(
        uncached_input_tokens: uncached_input_tokens,
        cached_input_tokens: cached_input_tokens,
        output_tokens: output_tokens,
        pricing_config: pricing_config
      )
      billed_cost_cents = calculate_billed_cost_cents(provider_cost_cents, pricing_config)

      balance_after = nil
      balance_before = nil
      already_processed_after_lock = false
      debit_transaction = nil
      response_id = response_payload[:response_id]
      begin
        wallet.with_lock do
          wallet.reload
          balance_before = wallet.balance_cents

          if AiUsageLog.exists?(account_id: account.id, message_id: message.id)
            already_processed_after_lock = true
            next
          end

          if wallet.balance_cents.to_i < billed_cost_cents
            return log_skip(account, conversation, message, SKIP_REASONS[:insufficient_balance], balance_before: wallet.balance_cents)
          end

          if billed_cost_cents.positive?
            wallet.update!(balance_cents: wallet.balance_cents - billed_cost_cents)
            debit_transaction = AiTransaction.create!(
              account: account,
              kind: :debit,
              amount_cents: billed_cost_cents,
              currency: wallet.currency,
              provider: 'openai',
              provider_ref: response_id,
              meta: {
                prompt_id: account.ai_prompt_id,
                prompt_version: account.ai_prompt_version,
                provider_cost_cents: provider_cost_cents,
                billed_cost_cents: billed_cost_cents,
                billing_multiplier: pricing_config.billing_multiplier,
                cached_input_tokens: cached_input_tokens,
                uncached_input_tokens: uncached_input_tokens
              }
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
            cost_cents: billed_cost_cents,
            provider_cost_cents: provider_cost_cents,
            billed_cost_cents: billed_cost_cents,
            billing_multiplier: pricing_config.billing_multiplier,
            currency: wallet.currency,
            meta: {
              provider: 'openai',
              response_id: response_payload[:response_id],
              raw_response: response_payload[:raw_response],
              cached_input_tokens: cached_input_tokens,
              uncached_input_tokens: uncached_input_tokens,
              pricing_source: pricing_config.source
            }
          )

          balance_after = wallet.balance_cents
        end
      rescue ActiveRecord::RecordNotUnique
        return log_skip(account, conversation, message, SKIP_REASONS[:already_processed], balance_before: wallet.reload.balance_cents)
      end

      return log_skip(account, conversation, message, SKIP_REASONS[:already_processed], balance_before: balance_before) if already_processed_after_lock

      begin
        normalized = normalize_ai_output(response_payload[:text])
        normalized_text = normalized[:text]
        log_event(
          event: 'normalized_reply',
          account: account,
          conversation: conversation,
          message: message,
          prompt_id: account.ai_prompt_id,
          prompt_version: account.ai_prompt_version,
          model: response_payload[:model],
          raw_is_json: normalized[:raw_is_json],
          ai_action: normalized[:action],
          ai_state: normalized[:state],
          fallback_used: normalized[:fallback_used],
          fallback_reason: normalized[:fallback_reason],
          missing_text_fields: normalized[:missing_text_fields]
        )
        params = ActionController::Parameters.new(
          content: normalized_text,
          message_type: 'outgoing',
          private: false,
          content_attributes: {
            ai_raw: normalized[:raw],
            ai_action: normalized[:action],
            ai_state: normalized[:state]
          }.compact
        )
        Messages::MessageBuilder.new(ai_user, conversation, params).perform
      rescue StandardError => e
        if debit_transaction && billed_cost_cents.positive?
          begin
            wallet.with_lock do
              wallet.reload
              wallet.update!(balance_cents: wallet.balance_cents + billed_cost_cents)
              AiTransaction.create!(
                account: account,
                kind: :refund,
                amount_cents: billed_cost_cents,
                currency: wallet.currency,
                provider: 'openai',
                provider_ref: response_id,
                meta: {
                  original_debit_id: debit_transaction.id,
                  reason: 'post_debit_delivery_failure',
                  error_class: e.class.to_s,
                  error_message: e.message.to_s.truncate(500)
                }
              )
              balance_after = wallet.balance_cents
            end
          rescue StandardError => refund_error
            log_event(
              event: 'refund_failed',
              account: account,
              conversation: conversation,
              message: message,
              error_class: refund_error.class.to_s,
              error_message: refund_error.message.to_s.truncate(200),
              reason: "original_debit_id=#{debit_transaction.id}"
            )
          end
        end
        raise e
      end

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
        cached_input_tokens: cached_input_tokens,
        uncached_input_tokens: uncached_input_tokens,
        output_tokens: output_tokens,
        total_tokens: total_tokens,
        cost_cents: billed_cost_cents,
        provider_cost_cents: provider_cost_cents,
        billed_cost_cents: billed_cost_cents,
        billing_multiplier: pricing_config.billing_multiplier,
        input_cost_per_1m: pricing_config.input_cost_per_1m,
        cached_input_cost_per_1m: pricing_config.cached_input_cost_per_1m,
        output_cost_per_1m: pricing_config.output_cost_per_1m,
        pricing_source: pricing_config.source,
        balance_before: balance_before,
        balance_after: balance_after
      )
    ensure
      release_processing_lock(message.id)
    end
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

    payload = { input: input_text, model: ai_model }
    if account.ai_prompt_id.present?
      prompt_obj = { id: account.ai_prompt_id }
      if account.ai_prompt_version.present?
        prompt_obj[:version] = account.ai_prompt_version.to_s
      end
      payload[:prompt] = prompt_obj
    end
    response_payload = call_openai(account, conversation, message, uri, api_key, payload)
    run_tool_loop(account, conversation, message, uri, api_key, response_payload)
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
      type = output['type']
      next unless %w[tool_call function_call].include?(type)

      {
        id: output['id'] || output['call_id'],
        call_id: output['call_id'] || output['id'],
        type: type,
        name: output['name'],
        arguments: output['arguments']
      }
    end
  end

  def run_tool_loop(account, conversation, message, uri, api_key, response_payload)
    policy = account.ai_tool_policy_with_defaults
    limits = policy['limits'] || {}
    max_tools_per_turn = limits['max_tools_per_turn'].to_i
    max_total_steps = limits['max_total_steps'].to_i
    max_tools_per_turn = 3 if max_tools_per_turn <= 0
    max_total_steps = 6 if max_total_steps <= 0

    tool_calls = extract_tool_calls(response_payload[:raw_response])
    return response_payload if tool_calls.empty?

    total_usage = accumulate_usage({ 'input_tokens' => 0, 'output_tokens' => 0, 'total_tokens' => 0,
                                     'input_tokens_details' => { 'cached_tokens' => 0 } }, response_payload[:usage])

    unless account.tool_calling_enabled?
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
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = Ai::Tools::ToolRegistry.execute(account: account, tool_call: tool_call, conversation: conversation, message: message)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        category = result[:category]
        args = result[:args].presence

        log_event(
          event: 'tool_call',
          account: account,
          conversation: conversation,
          message: message,
          prompt_id: account.ai_prompt_id,
          prompt_version: account.ai_prompt_version,
          tool_name: tool_name,
          tool_category: category,
          tool_args: args,
          step: steps
        )

        tool_payload = tool_payload_for(tool_name, result)
        tool_result_json = JSON.generate(tool_payload)

        if result[:error].present?
          log_event(
            event: 'tool_error',
            account: account,
            conversation: conversation,
            message: message,
            prompt_id: account.ai_prompt_id,
            prompt_version: account.ai_prompt_version,
            tool_name: tool_name,
            tool_category: category,
            tool_args: args,
            step: steps,
            duration_ms: duration_ms,
            reason: result[:error],
            error_class: result[:error_class],
            error_message: result[:error_message],
            tool_result: tool_result_json
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
            tool_category: category,
            tool_args: args,
            tool_result: tool_result_json,
            step: steps,
            duration_ms: duration_ms
          )
        end

        if tool_call[:type] == 'function_call'
          tool_results << {
            type: 'function_call_output',
            call_id: tool_call[:call_id] || tool_call[:id],
            output: tool_result_json
          }
        else
          tool_results << {
            type: 'tool_result',
            tool_call_id: tool_call[:id],
            content: tool_result_json
          }
        end
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
          tool_result_payload = JSON.generate(
            {
              status: 'error',
              tool: tool_name,
              error: 'tool_limit_exceeded'
            }
          )
          if tool_call[:type] == 'function_call'
            tool_results << {
              type: 'function_call_output',
              call_id: tool_call[:call_id] || tool_call[:id],
              output: tool_result_payload
            }
          else
            tool_results << {
              type: 'tool_result',
              tool_call_id: tool_call[:id],
              content: tool_result_payload
            }
          end
        end
      end

      break if tool_results.empty?

      log_event(
        event: 'tool_followup_start',
        account: account,
        conversation: conversation,
        message: message,
        prompt_id: account.ai_prompt_id,
        prompt_version: account.ai_prompt_version,
        model: ai_model,
        phase: 'followup',
        step: steps
      )

      followup_payload = {
        input: tool_results,
        previous_response_id: response_payload[:response_id],
        model: ai_model
      }

      response_payload = call_openai(account, conversation, message, uri, api_key, followup_payload)
      total_usage = accumulate_usage(total_usage, response_payload[:usage])
      tool_calls = extract_tool_calls(response_payload[:raw_response])
    end

    response_payload[:usage] = total_usage

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
    http.open_timeout = ENV.fetch('AI_OPENAI_OPEN_TIMEOUT', 5).to_i
    http.read_timeout = ENV.fetch('AI_OPENAI_READ_TIMEOUT', 120).to_i
    http.write_timeout = ENV.fetch('AI_OPENAI_WRITE_TIMEOUT', 30).to_i if http.respond_to?(:write_timeout=)
    request = Net::HTTP::Post.new(uri.request_uri)
    request['Authorization'] = "Bearer #{api_key}"
    request['Content-Type'] = 'application/json'
    if account.openai_project_id.present?
      request['OpenAI-Project'] = account.openai_project_id
    else
      log_event(
        event: 'missing_openai_project_error',
        account: account,
        conversation: conversation,
        message: message,
        reason: 'openai_project_id_blank'
      )
    end
    request.body = payload.to_json
    response = http.request(request)

    parsed = JSON.parse(response.body) rescue {}
    output_items = parsed['output'] || []
    output_types = output_items.map { |item| item['type'] }.compact
    first_tool_name = output_items.find { |item| %w[function_call tool_call].include?(item['type']) }&.fetch('name', nil)
    http_status = response.code.to_i
    parsed['_http_status'] = http_status
    error_message = nil
    if http_status >= 400
      error_message = extract_error_message(response.body, parsed)
      log_event(
        event: 'error',
        account: account,
        conversation: conversation,
        message: message,
        prompt_id: account.ai_prompt_id,
        prompt_version: account.ai_prompt_version,
        model: payload[:model] || parsed['model'],
        response_id: parsed['id'],
        reason: 'openai_error',
        http_status: http_status,
        error_message: error_message
      )
    end
    {
      text: http_status >= 400 ? nil : extract_text(parsed),
      usage: parsed['usage'],
      model: parsed['model'] || payload[:model],
      response_id: parsed['id'],
      raw_response: parsed,
      http_status: http_status,
      output_types: output_types,
      first_tool_name: first_tool_name,
      error: (http_status >= 400 ? 'openai_error' : nil),
      error_message: error_message
    }
  rescue *OPENAI_RETRYABLE_ERRORS => e
    log_event(
      event: 'error',
      account: account,
      conversation: conversation,
      message: message,
      prompt_id: account.ai_prompt_id,
      prompt_version: account.ai_prompt_version,
      model: payload[:model],
      reason: 'openai_transport_error',
      error_class: e.class.to_s,
      error_message: e.message.to_s.truncate(500)
    )
    raise
  end

  def extract_error_message(raw_body, parsed)
    message = parsed.dig('error', 'message') || parsed['message'] || raw_body.to_s
    message = message.to_s
    message.length > 3000 ? message[0, 3000] : message
  end

  def accumulate_usage(acc, incoming)
    return acc unless incoming.is_a?(Hash)

    acc['input_tokens'] = acc['input_tokens'].to_i + incoming['input_tokens'].to_i
    acc['output_tokens'] = acc['output_tokens'].to_i + incoming['output_tokens'].to_i
    incoming_total = incoming['total_tokens'].to_i
    incoming_total = incoming['input_tokens'].to_i + incoming['output_tokens'].to_i if incoming_total.zero?
    acc['total_tokens'] = acc['total_tokens'].to_i + incoming_total
    acc['input_tokens_details'] ||= { 'cached_tokens' => 0 }
    acc['input_tokens_details']['cached_tokens'] =
      acc['input_tokens_details']['cached_tokens'].to_i + incoming.dig('input_tokens_details', 'cached_tokens').to_i
    acc
  end

  def token_breakdown(input_tokens, usage)
    cached = usage.dig('input_tokens_details', 'cached_tokens').to_i
    cached = 0 if cached.negative?
    cached = [cached, input_tokens].min
    [cached, input_tokens - cached]
  end

  def calculate_provider_cost_cents(uncached_input_tokens:, cached_input_tokens:, output_tokens:, pricing_config:)
    input_rate = pricing_config.input_cost_per_1m
    output_rate = pricing_config.output_cost_per_1m
    cached_input_rate = pricing_config.cached_input_cost_per_1m
    cost = ((uncached_input_tokens * input_rate) + (cached_input_tokens * cached_input_rate) + (output_tokens * output_rate)) / 1_000_000.0
    cents = cost * 100
    return 0 if cents <= 0

    cents.ceil
  end

  def calculate_billed_cost_cents(provider_cost_cents, pricing_config)
    return 0 if provider_cost_cents.to_i <= 0

    billed_cents = provider_cost_cents.to_f * pricing_config.billing_multiplier
    billed_cents.ceil
  end

  def normalize_ai_output(raw_text)
    raw_string = raw_text.is_a?(String) ? raw_text : JSON.generate(raw_text)
    json_candidate = raw_text.is_a?(Hash) || raw_text.is_a?(Array) ? raw_string : extract_json_candidate(raw_string)
    return { text: raw_string, raw: raw_string, raw_is_json: false } if json_candidate.blank?

    parsed = JSON.parse(json_candidate)
    if parsed.is_a?(String)
      nested_candidate = extract_json_candidate(parsed)
      parsed = JSON.parse(nested_candidate) if nested_candidate.present?
    end
    return { text: raw_string, raw: raw_string, raw_is_json: false } unless parsed.is_a?(Hash)

    messages = parsed['messages']
    extracted = nil
    if messages.is_a?(Array)
      texts = messages.filter_map do |item|
        next unless item.is_a?(Hash)
        next unless item['type'] == 'text'

        text_value = item['text']
        text_value = text_value['value'] if text_value.is_a?(Hash)
        normalize_candidate_text(text_value)
      end
      extracted = texts.join("\n").presence
    end
    extracted ||= parsed.dig('data', 'message') ||
      parsed.dig('data', 'messages', 0, 'text') ||
      parsed['response'] ||
      parsed.dig('payload', 'message') ||
      parsed.dig('meta', 'message') ||
      parsed.dig('meta', 'reply') ||
      parsed['message'] ||
      parsed['reply'] ||
      parsed.dig('data', 'text') ||
      parsed.dig('data', 'content') ||
      parsed.dig('data', 'reply')
    extracted = normalize_candidate_text(extracted)
    action = parsed['action']
    state = parsed['state']
    fallback_used = false
    fallback_reason = nil
    missing_text_fields = nil
    if extracted.blank? && action == 'chat.reply'
      extracted = CHAT_REPLY_FALLBACK_TEXT
      fallback_used = true
      fallback_reason = 'missing_reply_payload'
      missing_text_fields = MISSING_REPLY_FIELDS
    end

    {
      text: extracted.presence || raw_string,
      raw: raw_string,
      raw_is_json: true,
      action: action,
      state: state,
      fallback_used: fallback_used,
      fallback_reason: fallback_reason,
      missing_text_fields: missing_text_fields
    }
  rescue JSON::ParserError => e
    log_event(
      event: 'normalize_error',
      account: nil,
      conversation: nil,
      message: nil,
      error_class: e.class.to_s,
      error_message: e.message.to_s.truncate(200)
    )
    { text: raw_string, raw: raw_string, raw_is_json: false }
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

  def normalize_candidate_text(value)
    case value
    when nil
      nil
    when String
      value
    when Hash
      value['text'] || value['message'] || value['content'] || value.to_json
    when Array
      texts = value.filter_map { |item| normalize_candidate_text(item) }
      texts.join("\n")
    else
      value.to_s
    end
  end

  def log_skip(account, conversation, message, reason, balance_before: nil)
    log_event(
      event: 'skip',
      account: account,
      conversation: conversation,
      message: message,
      prompt_id: account&.ai_prompt_id,
      prompt_version: account&.ai_prompt_version,
      model: ai_model,
      balance_before: balance_before,
      reason: reason,
      phase: 'initial'
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
    cached_input_tokens: nil,
    uncached_input_tokens: nil,
    output_tokens: nil,
    total_tokens: nil,
    cost_cents: nil,
    provider_cost_cents: nil,
    billed_cost_cents: nil,
    billing_multiplier: nil,
    input_cost_per_1m: nil,
    cached_input_cost_per_1m: nil,
    output_cost_per_1m: nil,
    pricing_source: nil,
    balance_before: nil,
    balance_after: nil,
    reason: nil,
    http_status: nil,
    tool_name: nil,
    tool_category: nil,
    tool_args: nil,
    tool_result: nil,
    step: nil,
    duration_ms: nil,
    error_class: nil,
    error_message: nil,
    output_types: nil,
    first_tool_name: nil,
    tools_source: 'prompt',
    phase: nil,
    raw_is_json: nil,
    ai_action: nil,
    ai_state: nil,
    fallback_used: nil,
    fallback_reason: nil,
    missing_text_fields: nil
  )
    payload = {
      event: event,
      reason: reason,
      tools_source: tools_source,
      phase: phase,
      raw_is_json: raw_is_json,
      ai_action: ai_action,
      ai_state: ai_state,
      fallback_used: fallback_used,
      fallback_reason: fallback_reason,
      missing_text_fields: missing_text_fields,
      account_id: account&.id,
      conversation_id: conversation&.id,
      message_id: message&.id,
      prompt_id: prompt_id,
      prompt_version: prompt_version,
      model: model,
      response_id: response_id,
      input_tokens: input_tokens,
      cached_input_tokens: cached_input_tokens,
      uncached_input_tokens: uncached_input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens,
      cost_cents: cost_cents,
      provider_cost_cents: provider_cost_cents,
      billed_cost_cents: billed_cost_cents,
      billing_multiplier: billing_multiplier,
      input_cost_per_1m: input_cost_per_1m,
      cached_input_cost_per_1m: cached_input_cost_per_1m,
      output_cost_per_1m: output_cost_per_1m,
      pricing_source: pricing_source,
      balance_before: balance_before,
      balance_after: balance_after,
      http_status: http_status,
      tool_name: tool_name,
      tool_category: tool_category,
      tool_args: tool_args,
      tool_result: tool_result,
      step: step,
      duration_ms: duration_ms,
      error_class: error_class,
      error_message: error_message,
      output_types: output_types,
      first_tool_name: first_tool_name
    }.compact
    level = case event.to_s
            when 'error', 'refund_failed' then :error
            when 'skip', 'tool_call' then :info
            else
              event.to_s.end_with?('_error') ? :warn : :info
            end
    Rails.logger.public_send(level, "[AI_REPLY] #{payload.to_json}")
  end

  def ai_model
    ENV['AI_MODEL'].presence || ENV['OPENAI_MODEL'].presence || 'gpt-5.1-2025-11-13'
  end

  def tool_payload_for(tool_name, result)
    error_code = result[:error].presence || result[:error_code].presence
    if error_code.present?
      {
        status: 'error',
        tool: tool_name,
        error_code: error_code,
        message: result[:message].presence || result[:error_message],
        details: result[:details]
      }.compact
    else
      content = result[:content]
      return content if content.is_a?(Hash)

      if content.present?
        { status: 'ok', tool: tool_name, result: content }
      else
        { status: 'ok', tool: tool_name }
      end
    end
  end

  def superseded_by_newer_incoming_message?(conversation, message)
    conversation.messages
                .where(message_type: :incoming, private: false)
                .where('id > ?', message.id)
                .exists?
  end

  def acquire_processing_lock(message_id)
    lock_key = message_id.to_i
    connection = ActiveRecord::Base.connection
    acquired = connection.select_value("SELECT pg_try_advisory_lock(#{PROCESSING_LOCK_NAMESPACE}, #{lock_key})")
    ActiveModel::Type::Boolean.new.cast(acquired)
  rescue StandardError => e
    log_event(
      event: 'lock_acquire_error',
      account: nil,
      conversation: nil,
      message: nil,
      error_class: e.class.to_s,
      error_message: e.message.to_s.truncate(200),
      reason: "message_id=#{message_id}"
    )
    true
  end

  def release_processing_lock(message_id)
    lock_key = message_id.to_i
    ActiveRecord::Base.connection.execute("SELECT pg_advisory_unlock(#{PROCESSING_LOCK_NAMESPACE}, #{lock_key})")
  rescue StandardError => e
    log_event(
      event: 'lock_release_error',
      account: nil,
      conversation: nil,
      message: nil,
      error_class: e.class.to_s,
      error_message: e.message.to_s.truncate(200),
      reason: "message_id=#{message_id}"
    )
  end
end
