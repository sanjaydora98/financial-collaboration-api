# frozen_string_literal: true

module ImportConstants
  STATUSES = {
    queued: "queued",
    running: "running",
    completed: "completed",
    failed: "failed"
  }.freeze

  IMPORTED_TRANSACTION_STATUSES = {
    pending: "pending",
    accepted: "accepted",
    rejected: "rejected"
  }.freeze

  BULK_REVIEW_MAX_IDS = 100
  REVIEW_ACTIONS = %w[accept reject].freeze
  TRANSACTION_ATTRIBUTES = %i[
    external_account_ref external_transaction_id amount currency merchant
    description category transaction_date
  ].freeze
end