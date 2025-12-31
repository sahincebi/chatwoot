class BackfillInstallationConfigSerializedValue < ActiveRecord::Migration[7.1]
  SUPPORT_KEYS = %w[SUPPORT_HQ_ACCOUNT_ID SUPPORT_HQ_INBOX_NAME SUPPORT_TICKET_SOURCE].freeze

  def up
    InstallationConfig.unscoped.where(serialized_value: nil).update_all(
      serialized_value: {},
      updated_at: Time.zone.now
    )
    InstallationConfig.unscoped.where(name: SUPPORT_KEYS, locked: true).update_all(
      locked: false,
      updated_at: Time.zone.now
    )
  end

  def down
    # No-op: this is a data backfill for NULLs.
  end
end
