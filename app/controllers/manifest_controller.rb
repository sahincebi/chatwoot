class ManifestController < ActionController::Base
  def show
    render json: {
      name: BrandingConfig.manifest_name,
      short_name: BrandingConfig.manifest_short_name,
      icons: manifest_icons,
      start_url: '/',
      display: 'standalone',
      background_color: '#1f93ff',
      theme_color: '#1f93ff'
    }
  end

  private

  def manifest_icons
    favicon_url = BrandingConfig.favicon_url
    return default_icons if favicon_url.blank?

    [
      {
        src: favicon_url,
        sizes: '512x512',
        type: icon_content_type(favicon_url)
      }
    ]
  end

  def icon_content_type(path)
    return 'image/svg+xml' if path.to_s.end_with?('.svg')

    'image/png'
  end

  def default_icons
    [
      { src: '/android-icon-36x36.png', sizes: '36x36', type: 'image/png', density: '0.75' },
      { src: '/android-icon-48x48.png', sizes: '48x48', type: 'image/png', density: '1.0' },
      { src: '/android-icon-72x72.png', sizes: '72x72', type: 'image/png', density: '1.5' },
      { src: '/android-icon-96x96.png', sizes: '96x96', type: 'image/png', density: '2.0' },
      { src: '/android-icon-144x144.png', sizes: '144x144', type: 'image/png', density: '3.0' },
      { src: '/android-icon-192x192.png', sizes: '192x192', type: 'image/png', density: '4.0' }
    ]
  end
end
