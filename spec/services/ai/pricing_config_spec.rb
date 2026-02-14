require 'rails_helper'

RSpec.describe Ai::PricingConfig do
  describe '.current' do
    it 'uses model catalog rates when explicit env/config overrides are missing' do
      allow(InstallationConfig).to receive(:get_value).with('AI_INPUT_COST_PER_1M').and_return(nil)
      allow(InstallationConfig).to receive(:get_value).with('AI_OUTPUT_COST_PER_1M').and_return(nil)
      allow(InstallationConfig).to receive(:get_value).with('AI_CACHED_INPUT_COST_PER_1M').and_return(nil)
      allow(InstallationConfig).to receive(:get_value).with('AI_BILLING_MULTIPLIER').and_return(nil)

      with_modified_env(
        'AI_INPUT_COST_PER_1M' => nil,
        'AI_OUTPUT_COST_PER_1M' => nil,
        'AI_CACHED_INPUT_COST_PER_1M' => nil,
        'AI_BILLING_MULTIPLIER' => nil
      ) do
        config = described_class.current(model: 'gpt-5.1-2025-11-13')
        expect(config.input_cost_per_1m).to eq(1.25)
        expect(config.output_cost_per_1m).to eq(10.0)
        expect(config.cached_input_cost_per_1m).to eq(0.125)
        expect(config.source[:input_cost_per_1m]).to eq('openai_model_catalog')
      end
    end

    it 'keeps env override precedence over model catalog rates' do
      allow(InstallationConfig).to receive(:get_value).and_return(nil)

      with_modified_env(
        'AI_INPUT_COST_PER_1M' => '3.0',
        'AI_OUTPUT_COST_PER_1M' => '9.0',
        'AI_CACHED_INPUT_COST_PER_1M' => '2.0'
      ) do
        config = described_class.current(model: 'gpt-5')
        expect(config.input_cost_per_1m).to eq(3.0)
        expect(config.output_cost_per_1m).to eq(9.0)
        expect(config.cached_input_cost_per_1m).to eq(2.0)
        expect(config.source[:input_cost_per_1m]).to eq('env')
      end
    end
  end
end
