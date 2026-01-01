require 'rails_helper'

RSpec.describe Ai::Tools::ToolRegistry do
  let(:account) { create(:account) }

  before do
    account.update!(
      ai_tool_policy: {
        'enabled' => true,
        'allowed_tools' => {
          'demo' => true,
          'email' => true,
          'conversation' => true,
          'calendar' => true
        },
        'limits' => { 'max_tools_per_turn' => 3, 'max_total_steps' => 6 }
      }
    )
  end

  it 'forces additionalProperties false for all registered tools' do
    schemas = described_class.tool_schemas_for(account)
    names = schemas.map { |schema| schema['name'] }

    expect(names).to match_array(described_class::TOOL_CONFIG.keys)
    schemas.each do |schema|
      expect(schema.dig('parameters', 'additionalProperties')).to eq(false)
    end
  end
end
