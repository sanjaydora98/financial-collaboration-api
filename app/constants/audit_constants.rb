# frozen_string_literal: true

module AuditConstants
  CATEGORIES = {
    crud: "crud",
    workflow: "workflow"
  }.freeze

  CRUD_EVENTS = {
    create: "create",
    update: "update",
    delete: "delete"
  }.freeze
  WORKFLOW_EVENTS = {
    submitted: "submitted",
    approved: "approved",
    rejected: "rejected",
    reimbursement_paid: "reimbursement_paid",
    import_accepted: "import_accepted",
    reimbursement_initiated: "reimbursement_initiated",
    reimbursement_failed: "reimbursement_failed"
  }.freeze

  EVENTS_BY_CATEGORY = {
    CATEGORIES[:crud] => CRUD_EVENTS.values.freeze,
    CATEGORIES[:workflow] => WORKFLOW_EVENTS.values.freeze
  }.freeze

  ACTOR_TYPES = {
    user: "user",
    system: "system"
  }.freeze

  REALTIME_EVENTS = {
    expense_created: "expense.created",
    expense_updated: "expense.updated",
    expense_deleted: "expense.deleted",
    expense_submitted: "expense.submitted",
    expense_approved: "expense.approved",
    expense_rejected: "expense.rejected",
    expense_reimbursed: "expense.reimbursed",
    reimbursement_updated: "reimbursement.updated",
    imported_transaction_accepted: "imported_transaction.accepted"
  }.freeze
end