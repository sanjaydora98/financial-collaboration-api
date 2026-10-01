module Expenses
  class Review
    DECISIONS = ApprovalConstants::DECISIONS.values.freeze

    def self.call(expense:, user:, decision:, rejection_reason: nil)
      raise ArgumentError, I18n.t("errors.approval.invalid_decision") unless DECISIONS.include?(decision)
      raise ArgumentError, I18n.t("errors.approval.rejection_reason_required") if decision == ApprovalConstants::DECISIONS[:reject] && rejection_reason.blank?

      expense.with_lock do
        membership = user.team_memberships.find_by(team_id: expense.team_id, active: true)
        raise Pundit::NotAuthorizedError unless membership
        raise Pundit::NotAuthorizedError unless ExpensePolicy.new(user, expense).approve?

        approval = expense.expense_approvals.find_by(
          approver_membership_id: membership.id,
          stage: membership.approval_stage
        )
        raise Pundit::NotAuthorizedError unless approval

        approval.lock!
        unless membership.approver? || membership.admin?
          raise Pundit::NotAuthorizedError
        end
        unless membership.approval_stage == approval.stage
          raise Pundit::NotAuthorizedError
        end
        raise WorkflowConflict unless expense.submitted? && expense.deleted_at.nil? && approval.pending?

        approval_before = approval.status
        finance_approval = nil

        if approval.manager? && decision == ApprovalConstants::DECISIONS[:approve]
          finance_approval = expense.expense_approvals.find_by(
            step: ApprovalConstants::STAGE_STEPS[ApprovalConstants::STAGES[:finance]],
            stage: ApprovalConstants::STAGES[:finance]
          )
          raise WorkflowConflict unless finance_approval&.queued?
          finance_approval.lock!
        elsif approval.manager? && decision == ApprovalConstants::DECISIONS[:reject]
          finance_approval = expense.expense_approvals.find_by(
            step: ApprovalConstants::STAGE_STEPS[ApprovalConstants::STAGES[:finance]],
            stage: ApprovalConstants::STAGES[:finance]
          )
          raise WorkflowConflict unless finance_approval&.queued?
          finance_approval.lock!
        end

        previous_expense_status = expense.status
        previous_finance_status = finance_approval&.status
        acted_at = Time.current
        approval.update!(
          status: ApprovalConstants::DECISION_STATUSES.fetch(decision),
          acted_at: acted_at,
          rejection_reason: decision == ApprovalConstants::DECISIONS[:reject] ? rejection_reason : nil
        )

        if approval.manager? && decision == ApprovalConstants::DECISIONS[:approve]
          finance_approval.update!(status: ApprovalConstants::STATUSES[:pending])
        elsif approval.manager? && decision == ApprovalConstants::DECISIONS[:reject]
          finance_approval.update!(status: ApprovalConstants::STATUSES[:skipped], acted_at: acted_at)
          update_expense_status(expense, membership, ExpenseConstants::STATUSES[:rejected])
        elsif approval.finance? && decision == ApprovalConstants::DECISIONS[:approve]
          update_expense_status(expense, membership, ExpenseConstants::STATUSES[:approved])
        elsif approval.finance? && decision == ApprovalConstants::DECISIONS[:reject]
          update_expense_status(expense, membership, ExpenseConstants::STATUSES[:rejected])
        end

        AuditLog.create!(
          team_id: expense.team_id,
          expense: expense,
          actor_membership: membership,
          actor_type: AuditConstants::ACTOR_TYPES[:user],
          category: AuditConstants::CATEGORIES[:workflow],
          event_type: decision == ApprovalConstants::DECISIONS[:approve] ? AuditConstants::WORKFLOW_EVENTS[:approved] : AuditConstants::WORKFLOW_EVENTS[:rejected],
          change_data: {
            before: {
              expense_status: previous_expense_status,
              approval_status: approval_before,
              finance_approval_status: previous_finance_status
            }.compact,
            after: {
              expense_status: expense.status,
              approval_stage: approval.stage,
              approval_status: approval.status,
              finance_approval_status: finance_approval&.status,
              decision: decision,
              rejection_reason: decision == ApprovalConstants::DECISIONS[:reject] ? rejection_reason : nil
            }.compact
          }
        )
      end

      expense
    end

    def self.update_expense_status(expense, membership, status)
      expense.audit_actor_membership_id = membership.id
      expense.update!(status: status)
    end
    private_class_method :update_expense_status
  end
end