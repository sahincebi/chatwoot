class NormalizeBooleanInstallationConfigs < ActiveRecord::Migration[7.0]
  def up
    boolean_keys = load_boolean_config_keys
    return if boolean_keys.empty?

    quoted_keys = boolean_keys.map { |key| connection.quote(key) }.join(', ')
    execute <<~SQL.squish
      UPDATE installation_configs
      SET serialized_value = jsonb_build_object(
            'value',
            CASE
              WHEN lower(coalesce(serialized_value->>'value', '')) IN ('true', 't', '1', 'yes', 'y', 'on')
                THEN 'true'::jsonb
              ELSE 'false'::jsonb
            END
          ),
          updated_at = CURRENT_TIMESTAMP
      WHERE name IN (#{quoted_keys})
    SQL

    GlobalConfig.clear_cache if defined?(GlobalConfig)
  end

  def down
    # no-op. values stay normalized as booleans.
  end

  private

  def load_boolean_config_keys
    config_path = Rails.root.join('config', 'installation_config.yml')
    configs = YAML.safe_load(File.read(config_path), aliases: true) || []
    configs.select { |config| config['type'] == 'boolean' }
           .map { |config| config['name'] }
           .compact
  end
end

