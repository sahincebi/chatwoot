class CreateAiIntegrations < ActiveRecord::Migration[7.0]
  def change
    if table_exists?(:ai_integrations)
      add_index :ai_integrations, [:account_id, :provider], unique: true,
                name: 'index_ai_integrations_on_account_id_and_provider' unless index_exists?(:ai_integrations, [:account_id, :provider], unique: true,
                                                                                            name: 'index_ai_integrations_on_account_id_and_provider')
      return
    end

    create_table :ai_integrations do |t|
      t.bigint :account_id, null: false
      t.string :provider, null: false
      t.boolean :enabled, null: false, default: false
      t.jsonb :settings, null: false, default: {}
      t.text :refresh_token
      t.text :access_token
      t.datetime :expires_at
      t.timestamps
    end

    add_index :ai_integrations, [:account_id, :provider], unique: true,
              name: 'index_ai_integrations_on_account_id_and_provider'
    add_foreign_key :ai_integrations, :accounts
  end
end
