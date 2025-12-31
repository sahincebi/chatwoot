class AddAiToolPolicyToAccounts < ActiveRecord::Migration[7.0]
  DEFAULT_AI_TOOL_POLICY = {
    'enabled' => false,
    'allowed_tools' => {},
    'limits' => {
      'max_tools_per_turn' => 3,
      'max_total_steps' => 8
    }
  }.freeze

  def change
    return if column_exists?(:accounts, :ai_tool_policy)

    add_column :accounts, :ai_tool_policy, :jsonb, null: false, default: DEFAULT_AI_TOOL_POLICY
  end
end
