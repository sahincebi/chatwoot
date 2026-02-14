class Ai::PricingConfig
  DEFAULT_INPUT_COST_PER_1M = 1.0
  DEFAULT_OUTPUT_COST_PER_1M = 1.0
  DEFAULT_CACHED_INPUT_COST_PER_1M = DEFAULT_INPUT_COST_PER_1M
  DEFAULT_BILLING_MULTIPLIER = 4.0

  CONFIG_KEYS = {
    input_cost_per_1m: 'AI_INPUT_COST_PER_1M',
    output_cost_per_1m: 'AI_OUTPUT_COST_PER_1M',
    cached_input_cost_per_1m: 'AI_CACHED_INPUT_COST_PER_1M',
    billing_multiplier: 'AI_BILLING_MULTIPLIER'
  }.freeze

  # OpenAI list prices per 1M token (USD). Can be overridden with ENV/InstallationConfig.
  MODEL_RATE_PATTERNS = [
    { pattern: /\Agpt-5-mini(\.|-|$)/i, input: 0.25, output: 2.0, cached_input: 0.025 },
    { pattern: /\Agpt-5-nano(\.|-|$)/i, input: 0.05, output: 0.4, cached_input: 0.005 },
    { pattern: /\Agpt-5(\.|-|$)/i, input: 1.25, output: 10.0, cached_input: 0.125 },
    { pattern: /\Agpt-4\.1-mini(\.|-|$)/i, input: 0.4, output: 1.6, cached_input: 0.1 },
    { pattern: /\Agpt-4\.1-nano(\.|-|$)/i, input: 0.1, output: 0.4, cached_input: 0.025 },
    { pattern: /\Agpt-4\.1(\.|-|$)/i, input: 2.0, output: 8.0, cached_input: 0.5 },
    { pattern: /\Agpt-4o-mini(\.|-|$)/i, input: 0.15, output: 0.6, cached_input: 0.075 },
    { pattern: /\Agpt-4o(\.|-|$)/i, input: 2.5, output: 10.0, cached_input: 1.25 }
  ].freeze

  attr_reader :model_name, :input_cost_per_1m, :output_cost_per_1m, :cached_input_cost_per_1m, :billing_multiplier, :source

  def self.current(model: nil)
    new(model: model)
  end

  def initialize(model: nil)
    @model_name = model.to_s.strip.presence
    model_rates = model_rate_for(@model_name)

    input_default = model_rates&.fetch(:input, nil) || DEFAULT_INPUT_COST_PER_1M
    input_source_default = model_rates ? 'openai_model_catalog' : 'default'
    @input_cost_per_1m, input_source = resolve_rate(
      env_key: CONFIG_KEYS[:input_cost_per_1m],
      default_value: input_default,
      default_source: input_source_default,
      allow_zero: true
    )

    output_default = model_rates&.fetch(:output, nil) || DEFAULT_OUTPUT_COST_PER_1M
    output_source_default = model_rates ? 'openai_model_catalog' : 'default'
    @output_cost_per_1m, output_source = resolve_rate(
      env_key: CONFIG_KEYS[:output_cost_per_1m],
      default_value: output_default,
      default_source: output_source_default,
      allow_zero: true
    )

    cached_default = model_rates&.fetch(:cached_input, nil) || @input_cost_per_1m || DEFAULT_CACHED_INPUT_COST_PER_1M
    cached_source_default = model_rates ? 'openai_model_catalog' : 'input_rate_fallback'
    @cached_input_cost_per_1m, cached_source = resolve_rate(
      env_key: CONFIG_KEYS[:cached_input_cost_per_1m],
      default_value: cached_default,
      default_source: cached_source_default,
      allow_zero: true
    )

    @billing_multiplier, multiplier_source = resolve_rate(
      env_key: CONFIG_KEYS[:billing_multiplier],
      default_value: DEFAULT_BILLING_MULTIPLIER,
      default_source: 'default',
      allow_zero: false
    )

    @source = {
      model_name: model_name,
      input_cost_per_1m: input_source,
      output_cost_per_1m: output_source,
      cached_input_cost_per_1m: cached_source,
      billing_multiplier: multiplier_source
    }
  end

  def as_h
    {
      model_name: model_name,
      input_cost_per_1m: input_cost_per_1m,
      output_cost_per_1m: output_cost_per_1m,
      cached_input_cost_per_1m: cached_input_cost_per_1m,
      billing_multiplier: billing_multiplier,
      source: source
    }
  end

  private

  def resolve_rate(env_key:, default_value:, default_source:, allow_zero:)
    env_value = parse_decimal(ENV[env_key], allow_zero: allow_zero)
    return [env_value, 'env'] if env_value

    config_value = parse_decimal(InstallationConfig.get_value(env_key), allow_zero: allow_zero)
    return [config_value, 'installation_config'] if config_value

    [default_value, default_source]
  end

  def model_rate_for(model)
    return nil if model.blank?

    MODEL_RATE_PATTERNS.each do |entry|
      return { input: entry[:input], output: entry[:output], cached_input: entry[:cached_input] } if model.match?(entry[:pattern])
    end

    nil
  end

  def parse_decimal(raw_value, allow_zero:)
    return nil if raw_value.nil?
    value = raw_value.to_f
    return nil unless value.finite?
    return nil if value.negative?
    return nil if !allow_zero && value.zero?

    value
  end
end
