require 'administrate/field/base'

class AiToolPolicyField < Administrate::Field::Base
  DEFAULT_LIMITS = {
    'max_tools_per_turn' => 3,
    'max_total_steps' => 8
  }.freeze
  CATEGORY_LABELS = {
    'calendar' => 'Takvim (musaitlik ve randevu olusturma)',
    'conversation' => 'Konusma (sohbet islemleri ve kapatma)',
    'demo' => 'Demo (demo senaryosu araclari)',
    'email' => 'E-posta (bilgilendirme ve gonderim)',
    'crm' => 'CRM (musteri notu ve etiket yazma)'
  }.freeze

  def enabled?
    policy['enabled'] == true
  end

  def allowed?(key)
    allowed_tools[key.to_s] == true
  end

  def max_tools_per_turn
    limits['max_tools_per_turn'].to_i.nonzero? || DEFAULT_LIMITS['max_tools_per_turn']
  end

  def max_total_steps
    limits['max_total_steps'].to_i.nonzero? || DEFAULT_LIMITS['max_total_steps']
  end

  def category_options
    categories = if defined?(Ai::Tools::ToolRegistry::TOOL_CONFIG)
                   Ai::Tools::ToolRegistry::TOOL_CONFIG.values.map { |config| config[:category].to_s }.uniq
                 else
                   []
                 end
    categories = %w[demo email conversation calendar crm] if categories.empty?
    categories.sort
  end

  def category_display_name(key)
    CATEGORY_LABELS[key.to_s] || "#{key} (ozel kategori)"
  end

  private

  def policy
    return {} unless data.is_a?(Hash)

    data.deep_stringify_keys
  end

  def allowed_tools
    value = policy['allowed_tools']
    value.is_a?(Hash) ? value.deep_stringify_keys : {}
  end

  def limits
    value = policy['limits']
    value.is_a?(Hash) ? DEFAULT_LIMITS.merge(value.deep_stringify_keys) : DEFAULT_LIMITS.dup
  end
end
