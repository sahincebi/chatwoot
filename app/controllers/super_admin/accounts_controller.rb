class SuperAdmin::AccountsController < SuperAdmin::ApplicationController
  # Overwrite any of the RESTful controller actions to implement custom behavior
  # For example, you may want to send an email after a foo is updated.
  #
  # def update
  #   super
  #   send_foo_updated_email(requested_resource)
  # end

  # Override this method to specify custom lookup behavior.
  # This will be used to set the resource for the `show`, `edit`, and `update`
  # actions.
  #
  # def find_resource(param)
  #   Foo.find_by!(slug: param)
  # end

  # The result of this lookup will be available as `requested_resource`

  # Override this if you have certain roles that require a subset
  # this will be used to set the records shown on the `index` action.
  #
  # def scoped_resource
  #   if current_user.super_admin?
  #     resource_class
  #   else
  #     resource_class.with_less_stuff
  #   end
  # end

  # Override `resource_params` if you want to transform the submitted
  # data before it's persisted. For example, the following would turn all
  # empty values into nil values. It uses other APIs such as `resource_class`
  # and `dashboard`:
  #
  def resource_params
    permitted_params = super
    permitted_params[:limits] = permitted_params[:limits].to_h.compact
    permitted_params[:selected_feature_flags] = params[:enabled_features].keys.map(&:to_sym) if params[:enabled_features].present?
    permitted_params[:ai_tool_policy] = normalize_ai_tool_policy(permitted_params[:ai_tool_policy], requested_resource)
    permitted_params
  end

  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information

  def seed
    Internal::SeedAccountJob.perform_later(requested_resource)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account seeding triggered')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def reset_cache
    requested_resource.reset_cache_keys
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Cache keys cleared')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def reprovision_openai
    requested_resource.update!(openai_project_id: nil, openai_project_status: :pending, openai_project_last_error: nil)
    Ai::OpenaiProjectProvisionJob.perform_later(requested_resource.id)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'OpenAI project reprovisioning enqueued.')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def destroy
    account = Account.find(params[:id])

    DeleteObjectJob.perform_later(account) if account.present?
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account deletion is in progress.')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  def normalize_ai_tool_policy(raw_policy, account)
    current_policy = account&.ai_tool_policy_with_defaults || Account::DEFAULT_AI_TOOL_POLICY.deep_dup
    policy = raw_policy.respond_to?(:to_h) ? raw_policy.to_h : {}
    policy = policy.deep_stringify_keys

    boolean_type = ActiveModel::Type::Boolean.new
    enabled = boolean_type.cast(policy['enabled'])
    enabled = current_policy['enabled'] if enabled.nil?

    allowed_tools = policy['allowed_tools'].is_a?(Hash) ? policy['allowed_tools'].deep_stringify_keys : {}
    allowed_tools = allowed_tools.transform_values { |value| boolean_type.cast(value) }

    limits = policy['limits'].is_a?(Hash) ? policy['limits'].deep_stringify_keys : {}
    max_tools_per_turn = limits['max_tools_per_turn'].to_i
    max_total_steps = limits['max_total_steps'].to_i

    {
      'enabled' => enabled,
      'allowed_tools' => current_policy['allowed_tools'].merge(allowed_tools),
      'limits' => {
        'max_tools_per_turn' => max_tools_per_turn.between?(1, 10) ? max_tools_per_turn : current_policy['limits']['max_tools_per_turn'],
        'max_total_steps' => max_total_steps.between?(1, 20) ? max_total_steps : current_policy['limits']['max_total_steps']
      }
    }
  end
end

SuperAdmin::AccountsController.prepend_mod_with('SuperAdmin::AccountsController')
