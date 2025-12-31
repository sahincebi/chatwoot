namespace :cebi do
  namespace :branding do
    desc 'Diagnose runtime branding config resolution for favicon/logo thumbnail'
    task diagnose: :environment do
      old_base = Cebi::ForceDarkBrandingService::DARK_ICON_BASE.sub('-dark', '')
      config_keys = %w[
        FAVICON_URL
        LOGO_THUMBNAIL
        BRAND_LOGO
        BRAND_LOGO_DARK
        BRAND_LOGO_LIGHT
        BRAND_LOGO_URL
        BRAND_LOGO_DARK_URL
        LOGO
        LOGO_DARK
      ]

      puts 'ENV'
      puts "  FAVICON_URL=#{ENV.fetch('FAVICON_URL', nil).inspect}"
      puts "  LOGO_THUMBNAIL=#{ENV.fetch('LOGO_THUMBNAIL', nil).inspect}"
      puts ''

      puts 'InstallationConfig'
      config_keys.each do |key|
        config = InstallationConfig.find_by(name: key)
        if config
          value = config.serialized_value.is_a?(Hash) ? (config.serialized_value['value'] || config.serialized_value[:value]) : config.value
          puts "  #{key}=#{value.inspect} locked=#{config.locked}"
        else
          puts "  #{key}=(missing)"
        end
      end
      puts ''

      global_config = GlobalConfig.get(*config_keys)
      resolved = global_config.merge(BrandingConfig.to_h)

      puts 'GlobalConfig'
      puts "  FAVICON_URL=#{global_config['FAVICON_URL'].inspect}"
      puts "  LOGO_THUMBNAIL=#{global_config['LOGO_THUMBNAIL'].inspect}"
      puts ''

      puts 'BrandingConfig'
      puts "  FAVICON_URL=#{BrandingConfig.favicon_url.inspect}"
      puts "  LOGO_THUMBNAIL=#{BrandingConfig.logo_thumbnail.inspect}"
      puts ''

      puts 'Resolved (dashboard layout)'
      puts "  FAVICON_URL=#{resolved['FAVICON_URL'].inspect}"
      puts "  LOGO_THUMBNAIL=#{resolved['LOGO_THUMBNAIL'].inspect}"
      puts ''

      puts 'Account overrides containing old favicon path'
      matches = 0
      columns = Account.columns.select { |col| [:string, :text].include?(col.type) }
      Account.find_each do |account|
        columns.each do |col|
          value = account.public_send(col.name)
          next unless value.is_a?(String) && value.include?(old_base)

          matches += 1
          puts "  account_id=#{account.id} column=#{col.name} value=#{value.inspect}"
        end
      end
      puts "  (none)" if matches.zero?
    end

    desc 'Force dark favicon/logo thumbnail defaults and clear caches'
    task force_dark: :environment do
      changes = Cebi::ForceDarkBrandingService.new.call

      puts 'InstallationConfig updates'
      if changes[:installation_configs].any?
        changes[:installation_configs].each do |change|
          puts "  #{change[:name]}: #{change[:from].inspect} -> #{change[:to].inspect} (locked_before=#{change[:locked_before]})"
        end
      else
        puts '  (no changes)'
      end
      puts ''

      puts 'Account updates'
      if changes[:accounts].any?
        changes[:accounts].each do |change|
          puts "  account_id=#{change[:account_id]} column=#{change[:column]} #{change[:from].inspect} -> #{change[:to].inspect}"
        end
      else
        puts '  (no changes)'
      end
    end
  end
end
