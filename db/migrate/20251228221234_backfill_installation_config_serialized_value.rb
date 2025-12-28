class BackfillInstallationConfigSerializedValue < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE installation_configs
      SET serialized_value = '{}'::jsonb
      WHERE serialized_value IS NULL
    SQL
  end

  def down
    # No-op: this is a data backfill for NULLs.
  end
end
