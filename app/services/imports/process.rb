module Imports
  class Process
    TRANSACTION_ATTRIBUTES = ImportConstants::TRANSACTION_ATTRIBUTES

    def self.call(import:, transactions:)
      import.with_lock do
        return import if import.completed?

        records = transaction_records(import, transactions)
        now = Time.current
        import.update!(status: ImportConstants::STATUSES[:running], started_at: now, finished_at: nil, error_summary: nil)
        ImportedTransaction.insert_all(
          records,
          unique_by: :index_imported_transactions_on_external_identity
        ) unless records.empty?
        import.update!(status: ImportConstants::STATUSES[:completed], finished_at: Time.current)
      end

      import
    rescue StandardError => error
      if import.persisted?
        import.with_lock do
          unless import.completed?
            import.update!(status: ImportConstants::STATUSES[:failed], finished_at: Time.current, error_summary: error.message.to_s.truncate(2_000))
          end
        end
      end
      raise
    end

    def self.transaction_records(import, transactions)
      Array(transactions).map do |attributes|
        attributes = attributes.to_h.symbolize_keys
        values = attributes.slice(*TRANSACTION_ATTRIBUTES).merge(
          team_id: import.team_id,
          import_id: import.id,
          provider: import.provider,
          status: ImportConstants::IMPORTED_TRANSACTION_STATUSES[:pending],
          created_at: Time.current,
          updated_at: Time.current
        )
        transaction = ImportedTransaction.new(values)
        raise ActiveRecord::RecordInvalid, transaction unless transaction.valid?

        values
      end
    end
    private_class_method :transaction_records
  end
end