class CreateAiWalletsTransactionsUsageLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :ai_wallets, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.bigint :balance_cents, null: false, default: 0
      t.string :currency, null: false, default: 'USD'
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    if table_exists?(:ai_wallets) && !check_constraint_exists?(:ai_wallets, name: 'ai_wallets_balance_cents_nonnegative')
      add_check_constraint :ai_wallets, 'balance_cents >= 0', name: 'ai_wallets_balance_cents_nonnegative'
    end

    create_table :ai_transactions, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :kind, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: 'USD'
      t.string :provider
      t.string :provider_ref
      t.jsonb :meta
      t.timestamps
    end

    add_index :ai_transactions, [:account_id, :created_at], if_not_exists: true
    add_index :ai_transactions, :provider_ref, if_not_exists: true

    create_table :ai_usage_logs, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :conversation_id
      t.bigint :message_id
      t.string :prompt_id
      t.integer :prompt_version
      t.string :model
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :total_tokens, null: false, default: 0
      t.bigint :cost_cents, null: false, default: 0
      t.string :currency, null: false, default: 'USD'
      t.jsonb :meta
      t.timestamps
    end

    add_index :ai_usage_logs, [:account_id, :created_at], if_not_exists: true
    add_index :ai_usage_logs, :conversation_id, if_not_exists: true
    add_index :ai_usage_logs, :message_id, if_not_exists: true
  end
end
