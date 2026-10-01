class ImportedTransactionSerializer
  FIELDS = %i[
    id team_id import_id provider external_account_ref external_transaction_id amount
    currency merchant description category transaction_date status reviewed_by_membership_id
    reviewed_at rejection_reason
  ].freeze

  def self.call(transaction)
    FIELDS.to_h { |field| [field, transaction.public_send(field)] }
  end
end