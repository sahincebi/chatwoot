class GlobalConfigService
  def self.load(config_key, default_value)
    config = GlobalConfig.get(config_key)[config_key]
    return config unless config.nil?

    # To support migrating existing instance relying on env variables
    # TODO: deprecate this later down the line
    config_value = ENV.fetch(config_key) { default_value }

    return if config_value.nil? || config_value == ''

    i = InstallationConfig.unscoped.find_or_initialize_by(name: config_key)
    if i.value.nil? || i.value == ''
      i.value = config_value
      i.locked = false if i.locked.nil?
      i.save!
    end

    # To clear a nil value that might have been cached in the previous call
    GlobalConfig.clear_cache
    i.value
  end
end
