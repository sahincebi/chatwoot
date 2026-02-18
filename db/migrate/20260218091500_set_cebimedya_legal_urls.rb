class SetCebimedyaLegalUrls < ActiveRecord::Migration[7.0]
  TERMS_URL = 'https://cebimedya.com/hizmet-sartlari'.freeze
  PRIVACY_URL = 'https://cebimedya.com/gizlilik-politikasi'.freeze

  def up
    upsert_installation_config('TERMS_URL', TERMS_URL)
    upsert_installation_config('PRIVACY_URL', PRIVACY_URL)
  end

  def down
    # no-op: keep legal URL overrides on rollback
  end

  private

  def upsert_installation_config(name, value)
    execute <<~SQL.squish
      INSERT INTO installation_configs (name, serialized_value, locked, created_at, updated_at)
      VALUES ('#{name}', '{"value":"#{value}"}'::jsonb, true, NOW(), NOW())
      ON CONFLICT (name)
      DO UPDATE SET serialized_value = EXCLUDED.serialized_value, updated_at = NOW()
    SQL
  end
end
