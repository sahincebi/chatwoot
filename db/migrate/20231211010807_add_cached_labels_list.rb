class AddCachedLabelsList < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :cached_label_list, :string unless column_exists?(:conversations, :cached_label_list)

    # NOTE: Some environments do not have ActsAsTaggableOn::Taggable::Cache loaded.
    # The column is the only mandatory schema change in this migration.
    if defined?(Conversation)
      Conversation.reset_column_information
      ActsAsTaggableOn::Taggable::Cache.included(Conversation) if defined?(ActsAsTaggableOn::Taggable::Cache)
    end
  end
end
