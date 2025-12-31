class AddIsAiAgentToUsers < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:users, :is_ai_agent)
      add_column :users, :is_ai_agent, :boolean, default: false, null: false
    end

    add_index :users, :is_ai_agent, if_not_exists: true
  end
end
