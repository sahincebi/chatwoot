class AddAdditionalAttributesToInboxes < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:inboxes, :additional_attributes)

    add_column :inboxes, :additional_attributes, :jsonb, null: false, default: {}
  end
end
