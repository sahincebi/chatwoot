module Cebi
  class ForceDarkBrandingService
    DARK_ICON_BASE = '/brand-assets/cebi-favicon-dark.svg'.freeze
    CACHE_BUST_VERSION = 'cebi-v9'.freeze
    DARK_ICON_PATH = "#{DARK_ICON_BASE}?v=#{CACHE_BUST_VERSION}".freeze
    OLD_ICON_BASE = DARK_ICON_BASE.sub('-dark', '').freeze
    TARGET_CONFIG_KEYS = %w[FAVICON_URL LOGO_THUMBNAIL].freeze

    def call
      changes = { installation_configs: [], accounts: [] }

      TARGET_CONFIG_KEYS.each do |key|
        change = upsert_installation_config(key)
        changes[:installation_configs] << change if change
      end

      changes[:accounts] = update_account_columns

      Rails.cache.clear
      GlobalConfig.clear_cache

      changes
    end

    private

    def upsert_installation_config(key)
      config = InstallationConfig.find_or_initialize_by(name: key)
      current_value = extract_config_value(config)
      locked_before = config.locked

      if current_value == DARK_ICON_PATH && config.persisted? && !locked_before
        return
      end

      config.serialized_value = normalized_serialized_value(config, DARK_ICON_PATH)
      config.locked = false
      config.save!

      { name: key, from: current_value, to: DARK_ICON_PATH, locked_before: locked_before }
    end

    def normalized_serialized_value(config, value)
      base = config.serialized_value.is_a?(Hash) ? config.serialized_value : {}
      base.merge('value' => value)
    end

    def extract_config_value(config)
      return nil if config.nil?
      return config.value unless config.serialized_value.is_a?(Hash)

      config.serialized_value['value'] || config.serialized_value[:value]
    end

    def update_account_columns
      results = []
      columns = Account.columns.select { |col| [:string, :text].include?(col.type) }

      Account.find_each do |account|
        updates = {}

        columns.each do |col|
          value = account.public_send(col.name)
          next unless value.is_a?(String) && value.include?(OLD_ICON_BASE)

          updates[col.name] = value.gsub(OLD_ICON_BASE, DARK_ICON_PATH)
          results << { account_id: account.id, column: col.name, from: value, to: updates[col.name] }
        end

        account.update_columns(updates) if updates.any?
      end

      results
    end
  end
end
