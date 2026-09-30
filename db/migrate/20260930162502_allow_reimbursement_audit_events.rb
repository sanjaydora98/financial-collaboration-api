class AllowReimbursementAuditEvents < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :audit_logs, name: "audit_logs_category_event_valid"
    add_check_constraint :audit_logs,
      "(category = 'crud' AND event_type IN ('create', 'update', 'delete')) OR " \
      "(category = 'workflow' AND event_type IN ('submitted', 'approved', 'rejected', 'reimbursement_paid', 'import_accepted', 'reimbursement_initiated', 'reimbursement_failed'))",
      name: "audit_logs_category_event_valid"
  end

  def down
    remove_check_constraint :audit_logs, name: "audit_logs_category_event_valid"
    add_check_constraint :audit_logs,
      "(category = 'crud' AND event_type IN ('create', 'update', 'delete')) OR " \
      "(category = 'workflow' AND event_type IN ('submitted', 'approved', 'rejected', 'reimbursement_paid', 'import_accepted'))",
      name: "audit_logs_category_event_valid"
  end
end
