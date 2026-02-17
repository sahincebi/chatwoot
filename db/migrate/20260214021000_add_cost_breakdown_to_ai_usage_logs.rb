class AddCostBreakdownToAiUsageLogs < ActiveRecord::Migration[7.0]
  def up
    unless column_exists?(:ai_usage_logs, :provider_cost_cents)
      add_column :ai_usage_logs, :provider_cost_cents, :bigint, null: false, default: 0
    end

    unless column_exists?(:ai_usage_logs, :billed_cost_cents)
      add_column :ai_usage_logs, :billed_cost_cents, :bigint, null: false, default: 0
    end

    unless column_exists?(:ai_usage_logs, :billing_multiplier)
      add_column :ai_usage_logs, :billing_multiplier, :decimal, precision: 8, scale: 4, null: false, default: 1.0
    end

    execute <<~SQL.squish
      UPDATE ai_usage_logs
      SET
        billed_cost_cents = COALESCE(NULLIF(billed_cost_cents, 0), COALESCE(cost_cents, 0)),
        provider_cost_cents = COALESCE(NULLIF(provider_cost_cents, 0), COALESCE(cost_cents, 0)),
        billing_multiplier = CASE
          WHEN COALESCE(provider_cost_cents, 0) <= 0 THEN 1.0
          ELSE ROUND(COALESCE(NULLIF(billed_cost_cents, 0), COALESCE(cost_cents, 0))::numeric / NULLIF(provider_cost_cents, 0), 4)
        END
    SQL
  end

  def down
    remove_column :ai_usage_logs, :billing_multiplier if column_exists?(:ai_usage_logs, :billing_multiplier)
    remove_column :ai_usage_logs, :billed_cost_cents if column_exists?(:ai_usage_logs, :billed_cost_cents)
    remove_column :ai_usage_logs, :provider_cost_cents if column_exists?(:ai_usage_logs, :provider_cost_cents)
  end
end
