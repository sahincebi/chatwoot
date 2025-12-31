class AddAiFieldsToAccounts < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:accounts, :ai_enabled)
      add_column :accounts, :ai_enabled, :boolean, default: true, null: false
    end

    unless column_exists?(:accounts, :ai_prompt_id)
      add_column :accounts, :ai_prompt_id, :string
    end

    unless column_exists?(:accounts, :ai_prompt_version)
      add_column :accounts, :ai_prompt_version, :integer, default: 1, null: false
    end

    unless column_exists?(:accounts, :ai_agent_user_id)
      add_column :accounts, :ai_agent_user_id, :bigint
    end

    add_index :accounts, :ai_agent_user_id, if_not_exists: true

    unless foreign_key_exists?(:accounts, :users, column: :ai_agent_user_id)
      add_foreign_key :accounts, :users, column: :ai_agent_user_id
    end
  end
end
