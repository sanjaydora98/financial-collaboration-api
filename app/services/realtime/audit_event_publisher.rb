module Realtime
  class AuditEventPublisher
    def self.call(audit_log)
      case [audit_log.category, audit_log.event_type]
      when [AuditConstants::CATEGORIES[:crud], AuditConstants::CRUD_EVENTS[:create]]
        publish_expense(audit_log, AuditConstants::REALTIME_EVENTS[:expense_created])
      when [AuditConstants::CATEGORIES[:crud], AuditConstants::CRUD_EVENTS[:update]]
        publish_expense(audit_log, AuditConstants::REALTIME_EVENTS[:expense_updated])
      when [AuditConstants::CATEGORIES[:crud], AuditConstants::CRUD_EVENTS[:delete]]
        publish_expense(audit_log, AuditConstants::REALTIME_EVENTS[:expense_deleted])
      when [AuditConstants::CATEGORIES[:workflow], AuditConstants::WORKFLOW_EVENTS[:submitted]]
        publish_expense(audit_log, AuditConstants::REALTIME_EVENTS[:expense_submitted])
      when [AuditConstants::CATEGORIES[:workflow], AuditConstants::WORKFLOW_EVENTS[:approved]]
        publish_expense(audit_log, AuditConstants::REALTIME_EVENTS[:expense_approved], approval_stage: audit_log.change_data.dig("after", "approval_stage"))
      when [AuditConstants::CATEGORIES[:workflow], AuditConstants::WORKFLOW_EVENTS[:rejected]]
        publish_expense(audit_log, AuditConstants::REALTIME_EVENTS[:expense_rejected], approval_stage: audit_log.change_data.dig("after", "approval_stage"))
      when [AuditConstants::CATEGORIES[:workflow], AuditConstants::WORKFLOW_EVENTS[:reimbursement_initiated]],
           [AuditConstants::CATEGORIES[:workflow], AuditConstants::WORKFLOW_EVENTS[:reimbursement_paid]],
           [AuditConstants::CATEGORIES[:workflow], AuditConstants::WORKFLOW_EVENTS[:reimbursement_failed]]
        publish_reimbursement(audit_log)
        publish_expense(audit_log, AuditConstants::REALTIME_EVENTS[:expense_reimbursed]) if audit_log.event_type == AuditConstants::WORKFLOW_EVENTS[:reimbursement_paid]
      when [AuditConstants::CATEGORIES[:workflow], AuditConstants::WORKFLOW_EVENTS[:import_accepted]]
        publish_imported_transaction_acceptance(audit_log)
      end
    rescue StandardError => error
      Rails.logger.error("Realtime audit mapping failed audit_log_id=#{audit_log.id} error=#{error.class}: #{error.message}")
      false
    end

    def self.publish_expense(audit_log, event, extra = {})
      expense = Expense.find_by(id: audit_log.expense_id)
      return unless expense

      Publisher.publish(
        team_id: expense.team_id,
        event: event,
        resource: {
          id: expense.id,
          status: expense.status,
          amount: expense.amount,
          currency: expense.currency,
          merchant: expense.merchant,
          category: expense.category,
          incurred_on: expense.incurred_on,
          lock_version: expense.lock_version
        }.merge(extra.compact)
      )
    end
    private_class_method :publish_expense

    def self.publish_reimbursement(audit_log)
      expense = Expense.find_by(id: audit_log.expense_id)
      reimbursement = expense&.reimbursement
      return unless expense && reimbursement

      Publisher.publish(
        team_id: expense.team_id,
        event: AuditConstants::REALTIME_EVENTS[:reimbursement_updated],
        resource: {
          id: reimbursement.id,
          expense_id: expense.id,
          status: reimbursement.status,
          amount: reimbursement.amount,
          currency: reimbursement.currency,
          paid_at: reimbursement.paid_at
        }
      )
    end
    private_class_method :publish_reimbursement

    def self.publish_imported_transaction_acceptance(audit_log)
      transaction_id = audit_log.change_data.dig("after", "imported_transaction_id")
      transaction = ImportedTransaction.find_by(id: transaction_id)
      return unless transaction

      Publisher.publish(
        team_id: transaction.team_id,
        event: AuditConstants::REALTIME_EVENTS[:imported_transaction_accepted],
        resource: { id: transaction.id, status: transaction.status, expense_id: audit_log.expense_id }
      )
    end
    private_class_method :publish_imported_transaction_acceptance
  end
end