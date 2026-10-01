class ImportSerializer
  FIELDS = %i[
    id team_id requested_by_membership_id provider idempotency_key status started_at
    finished_at error_summary
  ].freeze

  def self.call(import, imported_transaction_count: nil)
    FIELDS.to_h { |field| [field, import.public_send(field)] }.merge(
      imported_transaction_count: imported_transaction_count || import.imported_transactions.count
    )
  end
end