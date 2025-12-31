class AddIsSupportToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :is_support, :boolean, default: false, null: false
    add_index :inboxes, :is_support
  end
end
