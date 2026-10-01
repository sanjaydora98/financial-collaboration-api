class ExpenseSerializer
  FIELDS = %i[
    id team_id creator_membership_id member_membership_id amount currency merchant
    description category incurred_on status lock_version
    created_at updated_at
  ].freeze
  IMPORT_ACCEPT_FIELDS = %i[
    id team_id creator_membership_id member_membership_id imported_transaction_id
    amount currency merchant description category incurred_on status
  ].freeze

  def self.call(expense, imported_transaction: false)
    fields = imported_transaction ? IMPORT_ACCEPT_FIELDS : FIELDS
    fields.to_h { |field| [field, expense.public_send(field)] }
  end
end