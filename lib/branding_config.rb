class BrandingConfig
  class << self
    def installation_name
      value('INSTALLATION_NAME')
    end

    def brand_name
      value('BRAND_NAME', installation_name)
    end

    def brand_url
      value('BRAND_URL')
    end

    def widget_brand_url
      value('WIDGET_BRAND_URL', brand_url)
    end

    def logo
      value('LOGO')
    end

    def logo_dark
      value('LOGO_DARK')
    end

    def logo_thumbnail
      value('LOGO_THUMBNAIL')
    end

    def app_title
      value('APP_TITLE', installation_name)
    end

    def manifest_name
      value('MANIFEST_NAME', app_title)
    end

    def manifest_short_name
      value('MANIFEST_SHORT_NAME', manifest_name)
    end

    def favicon_url
      value('FAVICON_URL', logo_thumbnail)
    end

    def mailer_support_email
      value('MAILER_SUPPORT_EMAIL').presence || email_from_sender(ENV['MAILER_SENDER_EMAIL'])
    end

    def mailer_sender_email
      sender = ENV['MAILER_SENDER_EMAIL']
      return sender if sender.present?
      return if mailer_support_email.blank?

      "#{brand_name} <#{mailer_support_email}>"
    end

    def to_h
      {
        'INSTALLATION_NAME' => installation_name,
        'BRAND_NAME' => brand_name,
        'BRAND_URL' => brand_url,
        'WIDGET_BRAND_URL' => widget_brand_url,
        'LOGO' => logo,
        'LOGO_DARK' => logo_dark,
        'LOGO_THUMBNAIL' => logo_thumbnail,
        'APP_TITLE' => app_title,
        'MANIFEST_NAME' => manifest_name,
        'MANIFEST_SHORT_NAME' => manifest_short_name,
        'FAVICON_URL' => favicon_url,
        'MAILER_SUPPORT_EMAIL' => mailer_support_email
      }
    end

    private

    def value(key, default_value = nil)
      env_value = ENV[key]
      return env_value if env_value.present?

      config_value = GlobalConfig.get(key)[key]
      config_value.presence || default_value
    end

    def email_from_sender(sender)
      return if sender.blank?

      sender_match = sender.match(/<([^>]+)>/)
      sender_match ? sender_match[1] : sender
    end
  end
end
