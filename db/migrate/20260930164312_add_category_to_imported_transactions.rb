class AddCategoryToImportedTransactions < ActiveRecord::Migration[7.1]
  def change
    add_column :imported_transactions, :category, :string
  end
end
