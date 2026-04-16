class AddOpenaiProjectToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :openai_project_id, :string
    add_column :accounts, :openai_project_status, :integer, default: 0
    add_column :accounts, :openai_project_created_at, :datetime
    add_column :accounts, :openai_project_last_error, :text

    add_index :accounts, :openai_project_id, unique: true, where: 'openai_project_id IS NOT NULL'
  end
end
