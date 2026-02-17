class EnsureAiIntegrationsSchema < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:ai_integrations)

    add_column :ai_integrations, :account_id, :bigint unless column_exists?(:ai_integrations, :account_id)
    add_column :ai_integrations, :provider, :string unless column_exists?(:ai_integrations, :provider)
    add_column :ai_integrations, :enabled, :boolean, null: false, default: false unless column_exists?(:ai_integrations, :enabled)
    add_column :ai_integrations, :settings, :jsonb, null: false, default: {} unless column_exists?(:ai_integrations, :settings)
    add_column :ai_integrations, :refresh_token, :text unless column_exists?(:ai_integrations, :refresh_token)
    add_column :ai_integrations, :access_token, :text unless column_exists?(:ai_integrations, :access_token)
    add_column :ai_integrations, :expires_at, :datetime unless column_exists?(:ai_integrations, :expires_at)
    add_timestamps :ai_integrations, null: true unless column_exists?(:ai_integrations, :created_at)

    if column_exists?(:ai_integrations, :settings)
      execute <<~SQL.squish
        UPDATE ai_integrations
        SET settings = '{}'::jsonb
        WHERE settings IS NULL
      SQL
      change_column_default :ai_integrations, :settings, from: nil, to: {}
      change_column_null :ai_integrations, :settings, false
    end

    if column_exists?(:ai_integrations, :enabled)
      execute <<~SQL.squish
        UPDATE ai_integrations
        SET enabled = FALSE
        WHERE enabled IS NULL
      SQL
      change_column_default :ai_integrations, :enabled, from: nil, to: false
      change_column_null :ai_integrations, :enabled, false
    end

    if column_exists?(:ai_integrations, :account_id) && column_exists?(:ai_integrations, :provider)
      add_index :ai_integrations, [:account_id, :provider], unique: true,
                name: 'index_ai_integrations_on_account_id_and_provider' unless index_exists?(:ai_integrations, [:account_id, :provider], unique: true, name: 'index_ai_integrations_on_account_id_and_provider')
    end

    add_foreign_key :ai_integrations, :accounts unless foreign_key_exists?(:ai_integrations, :accounts)
  end

  def down
    # no-op: safety migration for divergent environments
  end
end
