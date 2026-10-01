module Imports
  class Request
    Result = Struct.new(:import, :created, :job_id, keyword_init: true)

    def self.call(team:, requested_by_membership:, provider:, idempotency_key:, transactions:)
      import, created = find_or_create_import(
        team: team,
        requested_by_membership: requested_by_membership,
        provider: provider,
        idempotency_key: idempotency_key
      )
      job_id = if import.queued? || import.failed?
        ProcessJob.perform_async(import.id, sanitized_transactions(transactions))
      end
      Result.new(import: import.reload, created: created, job_id: job_id)
    end

    def self.find_or_create_import(team:, requested_by_membership:, provider:, idempotency_key:)
      [
        Import.create!(
          team: team,
          requested_by_membership: requested_by_membership,
          provider: provider,
          idempotency_key: idempotency_key,
          status: ImportConstants::STATUSES[:queued]
        ),
        true
      ]
    rescue ActiveRecord::RecordNotUnique
      [Import.find_by!(team: team, provider: provider, idempotency_key: idempotency_key), false]
    end
    private_class_method :find_or_create_import

    def self.sanitized_transactions(transactions)
      Array(transactions).map do |attributes|
        attributes.to_h.symbolize_keys.slice(*Process::TRANSACTION_ATTRIBUTES).as_json
      end
    end
    private_class_method :sanitized_transactions
  end
end