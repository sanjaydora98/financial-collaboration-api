module Expenses
  class Submit
    def self.call(expense:, user:)
      expense.with_lock do
        membership = user.team_memberships.find_by(team_id: expense.team_id, active: true)
        raise Pundit::NotAuthorizedError unless membership
        raise Pundit::NotAuthorizedError unless ExpensePolicy.new(user, expense).submit?
        raise WorkflowConflict unless ExpenseConstants.transition_allowed?(expense.status, ExpenseConstants::STATUSES[:submitted]) && expense.deleted_at.nil?
        raise WorkflowConflict if expense.expense_approvals.exists?

        # NOTE: use a distinct local name here (not `membership`) so the submitter's
        # own membership resolved above is not clobbered; it is still needed below
        # to attribute the submit audit log to the actual submitting user.
        approvers = ApprovalConstants::INITIAL_STEPS.map do |step|
          stage_approver_membership = expense.team.team_memberships.where(
            active: true,
            role: [MembershipConstants::ROLES[:approver], MembershipConstants::ROLES[:admin]],
            approval_stage: step[:stage]
          ).first
          raise WorkflowConfigurationError, I18n.t("errors.approval.missing_approver", stage: step[:stage]) unless stage_approver_membership

          [step, stage_approver_membership]
        end

        before_status = expense.status
        submitted_at = Time.current
        approvers.each do |step, approver_membership|
          expense.expense_approvals.create!(
            team_id: expense.team_id,
            approver_membership: approver_membership,
            step: step[:step],
            stage: step[:stage],
            status: step[:status]
          )
        end

        expense.audit_actor_membership_id = membership.id
        expense.update!(status: ExpenseConstants::STATUSES[:submitted], submitted_at: submitted_at)
        AuditLog.create!(
          team_id: expense.team_id,
          expense: expense,
          actor_membership: membership,
          actor_type: AuditConstants::ACTOR_TYPES[:user],
          category: AuditConstants::CATEGORIES[:workflow],
          event_type: AuditConstants::WORKFLOW_EVENTS[:submitted],
          change_data: {
            before: { expense_status: before_status },
            after: {
              expense_status: expense.status,
              manager_approval_status: ApprovalConstants::STATUSES[:pending],
              finance_approval_status: ApprovalConstants::STATUSES[:queued]
            }
          }
        )
      end

      expense
    end
  end
end