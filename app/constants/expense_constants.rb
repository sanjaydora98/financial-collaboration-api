# frozen_string_literal: true

module ExpenseConstants
  STATUSES = {
    draft: "draft",
    submitted: "submitted",
    approved: "approved",
    rejected: "rejected",
    reimbursed: "reimbursed"
  }.freeze

  WORKFLOW_TRANSITIONS = {
    STATUSES[:draft] => [STATUSES[:submitted]],
    STATUSES[:submitted] => [STATUSES[:approved], STATUSES[:rejected]],
    STATUSES[:approved] => [STATUSES[:reimbursed]],
    STATUSES[:rejected] => [],
    STATUSES[:reimbursed] => []
  }.transform_values(&:freeze).freeze

  AUDIT_IGNORED_ATTRIBUTES = %w[created_at updated_at lock_version].freeze

  def self.transition_allowed?(from, to)
    WORKFLOW_TRANSITIONS.fetch(from, []).include?(to)
  end
end