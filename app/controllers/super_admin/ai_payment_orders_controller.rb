class SuperAdmin::AiPaymentOrdersController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:account, :user).order(created_at: :desc)
  end
end
