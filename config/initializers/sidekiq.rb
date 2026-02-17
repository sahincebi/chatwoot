require Rails.root.join('lib/redis/config')

BOOLEAN = ActiveModel::Type::Boolean.new

sidekiq_cron_enabled = lambda do
  explicit_value = ENV['SIDEKIQ_ENABLE_CRON']
  unless explicit_value.nil?
    next BOOLEAN.cast(explicit_value)
  end

  ENV['SIDEKIQ_ROLE'] != 'ai'
end

Sidekiq.configure_client do |config|
  config.redis = Redis::Config.app
end

# Logs whenever a job is pulled off Redis for execution.
class ChatwootDequeuedLogger
  def call(_worker, job, queue)
    payload = job['args'].first
    Sidekiq.logger.info("Dequeued #{job['wrapped']} #{payload['job_id']} from #{queue}")
    yield
  end
end

Sidekiq.configure_server do |config|
  config.redis = Redis::Config.app
  cron_enabled = sidekiq_cron_enabled.call
  config[:cron_poll_interval] = 0 unless cron_enabled

  if BOOLEAN.cast(ENV.fetch('ENABLE_SIDEKIQ_DEQUEUE_LOGGER', false))
    config.server_middleware do |chain|
      chain.add ChatwootDequeuedLogger
    end
  end

  # skip the default start stop logging
  if Rails.env.production?
    config.logger.formatter = Sidekiq::Logger::Formatters::JSON.new
    config[:skip_default_job_logging] = true
    config.logger.level = Logger.const_get(ENV.fetch('LOG_LEVEL', 'info').upcase.to_s)
  end
end
