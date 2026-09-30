module Expenses
  class Submit
    APPROVAL_STEPS = [
      { step: 1, stage: "manager", status: "pending" },
      { step: 2, stage: "finance", status: "queued" }
    ].freeze

    def self.call(expense:, user:)
      expense.with_lock do
        membership = user.team_memberships.find_by(team_id: expense.team_id, active: true)
        raise Pundit::NotAuthorizedError unless membership
        raise Pundit::NotAuthorizedError unless ExpensePolicy.new(user, expense).submit?
        raise WorkflowConflict unless expense.draft? && expense.deleted_at.nil?
        raise WorkflowConflict if expense.expense_approvals.exists?

        approvers = APPROVAL_STEPS.map do |step|
          membership = expense.team.team_memberships.where(
            active: true,
            role: %w[approver admin],
            approval_stage: step[:stage]
          ).first
          raise WorkflowConfigurationError, "No active #{step[:stage]} approver is configured." unless membership

          [step, membership]
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
        expense.update!(status: "submitted", submitted_at: submitted_at)
        AuditLog.create!(
          team_id: expense.team_id,
          expense: expense,
          actor_membership: membership,
          actor_type: "user",
          category: "workflow",
          event_type: "submitted",
          change_data: {
            before: { expense_status: before_status },
            after: {
              expense_status: expense.status,
              manager_approval_status: "pending",
              finance_approval_status: "queued"
            }
          }
        )
      end

      expense
    end
  end
end