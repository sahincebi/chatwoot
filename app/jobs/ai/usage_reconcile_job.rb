class Ai::UsageReconcileJob < ApplicationJob
  queue_as :low

  discard_on Ai::OpenaiUsageClient::MissingKeyError

  DRIFT_THRESHOLD = 2.0

  def perform
    end_time = Time.current
    start_time = 15.minutes.ago
    window = "#{start_time.iso8601}..#{end_time.iso8601}"

    response = Ai::OpenaiUsageClient.new.completions_usage(
      start_time: start_time.to_i,
      end_time: end_time.to_i
    )

    openai_total = extract_openai_total(response)
    if openai_total.nil?
      Rails.logger.warn("[UsageReconcile] unexpected response shape window=#{window}")
      return
    end

    local_total = local_total_tokens(start_time, end_time)

    drift = compute_drift(openai_total, local_total)
    line = "[UsageReconcile] drift=#{drift.round(2)}% openai=#{openai_total} local=#{local_total} window=#{window}"

    if drift > DRIFT_THRESHOLD
      Rails.logger.warn(line)
    else
      Rails.logger.info(line)
    end
  end

  private

  def extract_openai_total(response)
    data = response['data']
    return nil unless data.is_a?(Array)

    total = 0
    data.each do |bucket|
      results = bucket['results']
      next unless results.is_a?(Array)

      results.each do |row|
        total += row['input_tokens'].to_i + row['output_tokens'].to_i
      end
    end
    total
  end

  def local_total_tokens(start_time, end_time)
    AiUsageLog.where(created_at: start_time..end_time).sum('input_tokens + output_tokens').to_i
  end

  def compute_drift(openai_total, local_total)
    return 0.0 if openai_total.zero? && local_total.zero?
    return 100.0 if openai_total.zero?

    (openai_total - local_total).abs / openai_total.to_f * 100
  end
end
