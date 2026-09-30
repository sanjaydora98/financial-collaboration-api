module Realtime
  class AuditEventPublisher
    def self.call(audit_log)
      case [audit_log.category, audit_log.event_type]
      when ["crud", "create"]
        publish_expense(audit_log, "expense.created")
      when ["crud", "update"]
        publish_expense(audit_log, "expense.updated")
      when ["crud", "delete"]
        publish_expense(audit_log, "expense.deleted")
      when ["workflow", "submitted"]
        publish_expense(audit_log, "expense.submitted")
      when ["workflow", "approved"]
        publish_expense(audit_log, "expense.approved", approval_stage: audit_log.change_data.dig("after", "approval_stage"))
      when ["workflow", "rejected"]
        publish_expense(audit_log, "expense.rejected", approval_stage: audit_log.change_data.dig("after", "approval_stage"))
      when ["workflow", "reimbursement_initiated"], ["workflow", "reimbursement_paid"], ["workflow", "reimbursement_failed"]
        publish_reimbursement(audit_log)
        publish_expense(audit_log, "expense.reimbursed") if audit_log.event_type == "reimbursement_paid"
      when ["workflow", "import_accepted"]
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
        event: "reimbursement.updated",
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
        event: "imported_transaction.accepted",
        resource: { id: transaction.id, status: transaction.status, expense_id: audit_log.expense_id }
      )
    end
    private_class_method :publish_imported_transaction_acceptance
  end
end