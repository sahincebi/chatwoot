class AddUniqueIndexToAiUsageLogs < ActiveRecord::Migration[7.0]
  INDEX_NAME = 'index_ai_usage_logs_on_account_id_and_message_id_unique'

  def change
    return if index_exists?(:ai_usage_logs, [:account_id, :message_id], name: INDEX_NAME, unique: true)

    add_index :ai_usage_logs, [:account_id, :message_id], unique: true, name: INDEX_NAME
  end
end
