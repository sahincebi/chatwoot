class CreateAiPaymentOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_payment_orders do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :provider, null: false, default: 'paytr'
      t.string :merchant_oid, null: false
      t.integer :status, null: false, default: 0
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: 'USD'
      t.bigint :payment_amount_cents, null: false
      t.string :payment_currency, null: false, default: 'TRY'
      t.decimal :vat_rate, precision: 8, scale: 4, null: false, default: 0
      t.decimal :fx_rate, precision: 12, scale: 6, null: false, default: 0
      t.string :provider_ref
      t.string :paytr_status
      t.string :fail_reason_code
      t.string :fail_reason_message
      t.jsonb :meta, null: false, default: {}
      t.jsonb :raw_request, null: false, default: {}
      t.jsonb :raw_callback, null: false, default: {}
      t.datetime :paid_at
      t.datetime :failed_at
      t.timestamps
    end

    add_index :ai_payment_orders, :merchant_oid, unique: true
    add_index :ai_payment_orders, [:account_id, :status]
    add_check_constraint :ai_payment_orders, 'amount_cents > 0', name: 'ai_payment_orders_amount_cents_positive'
    add_check_constraint :ai_payment_orders, 'payment_amount_cents > 0', name: 'ai_payment_orders_payment_amount_cents_positive'
  end
end
