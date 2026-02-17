module SuperAdmin::FeaturesHelper
  def self.available_features
    YAML.load(ERB.new(Rails.root.join('app/helpers/super_admin/features.yml').read).result).with_indifferent_access
  end

  def self.plan_details
    plan = ChatwootHub.pricing_plan
    quantity = ChatwootHub.pricing_plan_quantity

    if plan == 'premium'
      "Su anda <span class='font-semibold'>#{quantity} temsilcili #{plan}</span> planindasiniz."
    else
      "Su anda <span class='font-semibold'>#{plan}</span> surum planindasiniz."
    end
  end
end
