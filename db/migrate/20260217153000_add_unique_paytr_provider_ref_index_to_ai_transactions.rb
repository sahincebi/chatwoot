class AddUniquePaytrProviderRefIndexToAiTransactions < ActiveRecord::Migration[7.0]
  INDEX_NAME = 'index_ai_transactions_on_account_provider_ref_paytr_unique'.freeze

  def up
    return unless table_exists?(:ai_transactions)
    return if index_exists?(:ai_transactions, [:account_id, :provider, :provider_ref], unique: true, name: INDEX_NAME)

    # Keep the earliest row if historical duplicate provider refs exist.
    deduplicate_paytr_provider_refs!

    add_index :ai_transactions,
              [:account_id, :provider, :provider_ref],
              unique: true,
              where: "provider = 'paytr' AND provider_ref IS NOT NULL",
              name: INDEX_NAME
  end

  def down
    remove_index :ai_transactions, name: INDEX_NAME if index_exists?(:ai_transactions, name: INDEX_NAME)
  end

  private

  def deduplicate_paytr_provider_refs!
    duplicate_groups = ai_transactions_scope
                       .group(:account_id, :provider_ref)
                       .having('COUNT(*) > 1')
                       .pluck(:account_id, :provider_ref)

    duplicate_groups.each do |account_id, provider_ref|
      ai_transactions_scope
        .where(account_id: account_id, provider_ref: provider_ref)
        .order(:id)
        .offset(1)
        .delete_all
    end
  end

  def ai_transactions_scope
    ai_transaction_model.where(provider: 'paytr').where.not(provider_ref: nil)
  end

  def ai_transaction_model
    @ai_transaction_model ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'ai_transactions'
    end
  end
end
