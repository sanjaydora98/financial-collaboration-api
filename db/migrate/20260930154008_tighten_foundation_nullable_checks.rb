class TightenFoundationNullableChecks < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :team_memberships, name: "team_memberships_role_approval_stage_valid"
    add_check_constraint :team_memberships,
      "(role IN ('creator', 'viewer') AND approval_stage IS NULL) OR " \
      "(role = 'approver' AND approval_stage IS NOT NULL AND approval_stage IN ('manager', 'finance')) OR " \
      "(role = 'admin' AND (approval_stage IS NULL OR approval_stage IN ('manager', 'finance')))" ,
      name: "team_memberships_role_approval_stage_valid"

    remove_check_constraint :expense_approvals, name: "expense_approvals_rejection_reason_valid"
    add_check_constraint :expense_approvals,
      "(status = 'rejected' AND rejection_reason IS NOT NULL AND btrim(rejection_reason) <> '') OR " \
      "(status <> 'rejected' AND rejection_reason IS NULL)",
      name: "expense_approvals_rejection_reason_valid"

    remove_check_constraint :reimbursements, name: "reimbursements_failure_reason_valid"
    add_check_constraint :reimbursements,
      "(status = 'failed' AND failure_reason IS NOT NULL AND btrim(failure_reason) <> '') OR " \
      "(status <> 'failed' AND failure_reason IS NULL)",
      name: "reimbursements_failure_reason_valid"

    remove_check_constraint :imported_transactions, name: "imported_transactions_review_fields_valid"
    add_check_constraint :imported_transactions,
      "(status = 'pending' AND reviewed_by_membership_id IS NULL AND reviewed_at IS NULL AND rejection_reason IS NULL) OR " \
      "(status = 'accepted' AND reviewed_by_membership_id IS NOT NULL AND reviewed_at IS NOT NULL AND rejection_reason IS NULL) OR " \
      "(status = 'rejected' AND reviewed_by_membership_id IS NOT NULL AND reviewed_at IS NOT NULL AND rejection_reason IS NOT NULL AND btrim(rejection_reason) <> '')",
      name: "imported_transactions_review_fields_valid"
  end

  def down
    remove_check_constraint :team_memberships, name: "team_memberships_role_approval_stage_valid"
    add_check_constraint :team_memberships,
      "(role IN ('creator', 'viewer') AND approval_stage IS NULL) OR " \
      "(role = 'approver' AND approval_stage IN ('manager', 'finance')) OR " \
      "(role = 'admin' AND (approval_stage IS NULL OR approval_stage IN ('manager', 'finance')))" ,
      name: "team_memberships_role_approval_stage_valid"

    remove_check_constraint :expense_approvals, name: "expense_approvals_rejection_reason_valid"
    add_check_constraint :expense_approvals,
      "(status = 'rejected' AND btrim(rejection_reason) <> '') OR " \
      "(status <> 'rejected' AND rejection_reason IS NULL)",
      name: "expense_approvals_rejection_reason_valid"

    remove_check_constraint :reimbursements, name: "reimbursements_failure_reason_valid"
    add_check_constraint :reimbursements,
      "(status = 'failed' AND btrim(failure_reason) <> '') OR (status <> 'failed' AND failure_reason IS NULL)",
      name: "reimbursements_failure_reason_valid"

    remove_check_constraint :imported_transactions, name: "imported_transactions_review_fields_valid"
    add_check_constraint :imported_transactions,
      "(status = 'pending' AND reviewed_by_membership_id IS NULL AND reviewed_at IS NULL AND rejection_reason IS NULL) OR " \
      "(status = 'accepted' AND reviewed_by_membership_id IS NOT NULL AND reviewed_at IS NOT NULL AND rejection_reason IS NULL) OR " \
      "(status = 'rejected' AND reviewed_by_membership_id IS NOT NULL AND reviewed_at IS NOT NULL AND btrim(rejection_reason) <> '')",
      name: "imported_transactions_review_fields_valid"
  end
end
