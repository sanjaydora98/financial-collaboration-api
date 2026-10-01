module Reimbursements
  class Conflict < StandardError; end

  class Create
    def self.call(expense:, user:)
      expense.with_lock do
        membership = user.team_memberships.find_by(team_id: expense.team_id, active: true)
        raise Pundit::NotAuthorizedError unless membership
        raise Pundit::NotAuthorizedError unless ExpensePolicy.new(user, expense).initiate_reimbursement?
        raise Conflict unless expense.approved? && expense.deleted_at.nil?
        raise Conflict if expense.reimbursement.present?

        reimbursement = expense.build_reimbursement(
          team_id: expense.team_id,
          initiated_by_membership: membership,
          amount: expense.amount,
          currency: expense.currency,
          status: ReimbursementConstants::STATUSES[:pending]
        )
        reimbursement.save!

        Settlement.write_audit(
          expense: expense,
          membership: membership,
          event_type: AuditConstants::WORKFLOW_EVENTS[:reimbursement_initiated],
          before: { expense_status: expense.status, reimbursement_status: nil },
          after: { expense_status: expense.status, reimbursement_status: reimbursement.status, reimbursement_id: reimbursement.id }
        )

        result = PaymentSimulator.call(reimbursement: reimbursement)
        Settlement.call(reimbursement: reimbursement, expense: expense, membership: membership, result: result)

        reimbursement
      end
    end
  end

  class Settlement
    def self.call(reimbursement:, expense:, membership:, result:)
      case result.status
      when ReimbursementConstants::STATUSES[:paid]
        previous_expense_status = expense.status
        previous_reimbursement_status = reimbursement.status
        paid_at = Time.current
        reimbursement.update!(status: ReimbursementConstants::STATUSES[:paid], paid_at: paid_at)
        expense.audit_actor_membership_id = membership.id
        expense.update!(status: ExpenseConstants::STATUSES[:reimbursed])
        write_audit(
          expense: expense,
          membership: membership,
          event_type: AuditConstants::WORKFLOW_EVENTS[:reimbursement_paid],
          before: { expense_status: previous_expense_status, reimbursement_status: previous_reimbursement_status },
          after: { expense_status: expense.status, reimbursement_status: reimbursement.status, paid_at: paid_at }
        )
      when ReimbursementConstants::STATUSES[:failed]
        failure_reason = result.failure_reason.presence || "Simulated settlement failure"
        previous_expense_status = expense.status
        previous_reimbursement_status = reimbursement.status
        reimbursement.update!(status: ReimbursementConstants::STATUSES[:failed], failure_reason: failure_reason)
        write_audit(
          expense: expense,
          membership: membership,
          event_type: AuditConstants::WORKFLOW_EVENTS[:reimbursement_failed],
          before: { expense_status: previous_expense_status, reimbursement_status: previous_reimbursement_status },
          after: { expense_status: expense.status, reimbursement_status: reimbursement.status, failure_reason: failure_reason }
        )
      else
        raise ArgumentError, "Unsupported internal payment result."
      end
    end

    def self.write_audit(expense:, membership:, event_type:, before:, after:)
      AuditLog.create!(
        team_id: expense.team_id,
        expense: expense,
        actor_membership: membership,
        actor_type: AuditConstants::ACTOR_TYPES[:user],
        category: AuditConstants::CATEGORIES[:workflow],
        event_type: event_type,
        change_data: { before: before, after: after }
      )
    end
  end

  class Retry
    def self.call(reimbursement:, user:)
      expense = reimbursement.expense
      expense.with_lock do
        membership = user.team_memberships.find_by(team_id: expense.team_id, active: true)
        raise Pundit::NotAuthorizedError unless membership
        raise Pundit::NotAuthorizedError unless ExpensePolicy.new(user, expense).initiate_reimbursement?

        reimbursement.reload
        reimbursement.lock!
        raise Conflict unless reimbursement.failed? && expense.approved? && expense.deleted_at.nil?

        previous_status = reimbursement.status
        reimbursement.update!(status: ReimbursementConstants::STATUSES[:pending], failure_reason: nil, paid_at: nil)
        Settlement.write_audit(
          expense: expense,
          membership: membership,
          event_type: AuditConstants::WORKFLOW_EVENTS[:reimbursement_initiated],
          before: { expense_status: expense.status, reimbursement_status: previous_status },
          after: {
            expense_status: expense.status,
            reimbursement_status: reimbursement.status,
            reimbursement_id: reimbursement.id
          }
        )

        result = PaymentSimulator.call(reimbursement: reimbursement)
        Settlement.call(reimbursement: reimbursement, expense: expense, membership: membership, result: result)
        reimbursement
      end
    end
  end
end