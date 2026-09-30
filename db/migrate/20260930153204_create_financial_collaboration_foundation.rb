class CreateFinancialCollaborationFoundation < ActiveRecord::Migration[7.1]
  def up
    create_table :users do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :password_digest, null: false
      t.column :disabled_at, "timestamp with time zone"
      add_timestamps_with_timezone(t, updated: true)
    end
    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"
    add_check_constraint :users, "email = lower(email) AND btrim(email) <> '' AND btrim(name) <> ''", name: "users_email_name_nonblank"

    create_table :auth_sessions do |t|
      t.references :user, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.string :token_digest, limit: 64, null: false
      t.column :expires_at, "timestamp with time zone", null: false
      t.column :revoked_at, "timestamp with time zone"
      t.column :last_used_at, "timestamp with time zone"
      add_timestamps_with_timezone(t, updated: false)
    end
    add_index :auth_sessions, :token_digest, unique: true
    add_index :auth_sessions, [:user_id, :expires_at]
    add_check_constraint :auth_sessions, "btrim(token_digest) <> ''", name: "auth_sessions_token_digest_nonblank"

    create_table :teams do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.references :created_by, null: false, index: false, foreign_key: { to_table: :users, on_delete: :restrict }
      add_timestamps_with_timezone(t)
    end
    add_index :teams, :slug, unique: true
    add_check_constraint :teams, "btrim(name) <> '' AND btrim(slug) <> ''", name: "teams_name_slug_nonblank"

    create_table :team_memberships do |t|
      t.references :team, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.references :user, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.string :role, null: false
      t.string :approval_stage
      t.boolean :active, null: false, default: true
      add_timestamps_with_timezone(t)
    end
    add_index :team_memberships, [:team_id, :user_id], unique: true
    add_index :team_memberships, [:team_id, :id], unique: true, name: "index_team_memberships_on_team_and_id"
    add_index :team_memberships, [:user_id, :team_id]
    add_index :team_memberships, [:team_id, :approval_stage], unique: true,
      where: "active AND approval_stage IS NOT NULL AND role IN ('approver', 'admin')",
      name: "index_active_team_approvers_on_team_and_stage"
    add_check_constraint :team_memberships,
      "(role IN ('creator', 'viewer') AND approval_stage IS NULL) OR " \
      "(role = 'approver' AND approval_stage IS NOT NULL AND approval_stage IN ('manager', 'finance')) OR " \
      "(role = 'admin' AND (approval_stage IS NULL OR approval_stage IN ('manager', 'finance')))" ,
      name: "team_memberships_role_approval_stage_valid"
    add_check_constraint :team_memberships, "role IN ('creator', 'approver', 'viewer', 'admin')", name: "team_memberships_role_valid"

    create_table :imports do |t|
      t.references :team, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.bigint :requested_by_membership_id, null: false
      t.string :provider, null: false
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "queued"
      t.column :started_at, "timestamp with time zone"
      t.column :finished_at, "timestamp with time zone"
      t.text :error_summary
      add_timestamps_with_timezone(t)
    end
    add_index :imports, [:team_id, :provider, :idempotency_key], unique: true, name: "index_imports_on_team_provider_idempotency"
    add_index :imports, [:team_id, :id], unique: true, name: "index_imports_on_team_and_id"
    add_index :imports, [:team_id, :status, :created_at]
    add_check_constraint :imports, "status IN ('queued', 'running', 'completed', 'failed')", name: "imports_status_valid"
    add_check_constraint :imports, "btrim(provider) <> '' AND btrim(idempotency_key) <> ''", name: "imports_provider_key_nonblank"

    create_table :imported_transactions do |t|
      t.references :team, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.bigint :import_id, null: false
      t.string :provider, null: false
      t.string :external_account_ref, null: false
      t.string :external_transaction_id, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, limit: 3, null: false
      t.string :merchant, null: false
      t.text :description
      t.date :transaction_date, null: false
      t.jsonb :raw_payload
      t.string :status, null: false, default: "pending"
      t.bigint :reviewed_by_membership_id
      t.column :reviewed_at, "timestamp with time zone"
      t.text :rejection_reason
      add_timestamps_with_timezone(t)
    end
    add_index :imported_transactions, [:team_id, :provider, :external_account_ref, :external_transaction_id],
      unique: true, name: "index_imported_transactions_on_external_identity"
    add_index :imported_transactions, [:team_id, :id], unique: true, name: "index_imported_transactions_on_team_and_id"
    add_index :imported_transactions, [:team_id, :transaction_date],
      where: "status = 'pending'", name: "index_pending_imported_transactions_by_team_date"
    add_check_constraint :imported_transactions, "amount > 0", name: "imported_transactions_amount_positive"
    add_check_constraint :imported_transactions, "currency ~ '^[A-Z]{3}$'", name: "imported_transactions_currency_format"
    add_check_constraint :imported_transactions, "status IN ('pending', 'accepted', 'rejected')", name: "imported_transactions_status_valid"
    add_check_constraint :imported_transactions,
      "(status = 'pending' AND reviewed_by_membership_id IS NULL AND reviewed_at IS NULL AND rejection_reason IS NULL) OR " \
      "(status = 'accepted' AND reviewed_by_membership_id IS NOT NULL AND reviewed_at IS NOT NULL AND rejection_reason IS NULL) OR " \
      "(status = 'rejected' AND reviewed_by_membership_id IS NOT NULL AND reviewed_at IS NOT NULL AND rejection_reason IS NOT NULL AND btrim(rejection_reason) <> '')",
      name: "imported_transactions_review_fields_valid"
    add_check_constraint :imported_transactions,
      "btrim(provider) <> '' AND btrim(external_account_ref) <> '' AND " \
      "btrim(external_transaction_id) <> '' AND btrim(merchant) <> ''",
      name: "imported_transactions_source_fields_nonblank"

    create_table :expenses do |t|
      t.references :team, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.bigint :creator_membership_id, null: false
      t.bigint :member_membership_id, null: false
      t.bigint :imported_transaction_id
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, limit: 3, null: false
      t.string :merchant, null: false
      t.text :description
      t.string :category
      t.date :incurred_on, null: false
      t.string :status, null: false, default: "draft"
      t.column :submitted_at, "timestamp with time zone"
      t.column :deleted_at, "timestamp with time zone"
      t.integer :lock_version, null: false, default: 0
      add_timestamps_with_timezone(t)
    end
    add_index :expenses, [:team_id, :id], unique: true, name: "index_expenses_on_team_and_id"
    add_index :expenses, [:team_id, :status, :created_at]
    add_index :expenses, [:team_id, :member_membership_id, :created_at], name: "index_expenses_on_team_member_and_created_at"
    add_index :expenses, [:team_id, :creator_membership_id, :status, :created_at], name: "index_expenses_on_team_creator_status_created"
    add_index :expenses, :imported_transaction_id, unique: true
    add_check_constraint :expenses, "amount > 0", name: "expenses_amount_positive"
    add_check_constraint :expenses, "currency ~ '^[A-Z]{3}$'", name: "expenses_currency_format"
    add_check_constraint :expenses, "status IN ('draft', 'submitted', 'approved', 'rejected', 'reimbursed')", name: "expenses_status_valid"
    add_check_constraint :expenses, "lock_version >= 0", name: "expenses_lock_version_nonnegative"
    add_check_constraint :expenses, "btrim(merchant) <> ''", name: "expenses_merchant_nonblank"

    create_table :expense_approvals do |t|
      t.references :team, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.bigint :expense_id, null: false
      t.integer :step, null: false, limit: 2
      t.string :stage, null: false
      t.bigint :approver_membership_id, null: false
      t.string :status, null: false
      t.column :acted_at, "timestamp with time zone"
      t.text :rejection_reason
      add_timestamps_with_timezone(t)
    end
    add_index :expense_approvals, [:team_id, :expense_id, :step, :approver_membership_id],
      unique: true, name: "index_expense_approvals_on_expense_step_approver"
    add_index :expense_approvals, [:team_id, :approver_membership_id, :status, :created_at],
      name: "index_expense_approvals_on_approver_queue"
    add_check_constraint :expense_approvals, "step > 0", name: "expense_approvals_step_positive"
    add_check_constraint :expense_approvals,
      "(step = 1 AND stage = 'manager') OR (step = 2 AND stage = 'finance')",
      name: "expense_approvals_step_stage_valid"
    add_check_constraint :expense_approvals,
      "status IN ('queued', 'pending', 'approved', 'rejected', 'skipped')",
      name: "expense_approvals_status_valid"
    add_check_constraint :expense_approvals,
      "(status IN ('queued', 'pending') AND acted_at IS NULL) OR " \
      "(status IN ('approved', 'rejected', 'skipped') AND acted_at IS NOT NULL)",
      name: "expense_approvals_decision_timestamp_valid"
    add_check_constraint :expense_approvals,
      "(status = 'rejected' AND rejection_reason IS NOT NULL AND btrim(rejection_reason) <> '') OR " \
      "(status <> 'rejected' AND rejection_reason IS NULL)",
      name: "expense_approvals_rejection_reason_valid"

    create_table :reimbursements do |t|
      t.references :team, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.bigint :expense_id, null: false
      t.bigint :initiated_by_membership_id, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, limit: 3, null: false
      t.string :status, null: false, default: "pending"
      t.string :external_reference
      t.column :paid_at, "timestamp with time zone"
      t.text :failure_reason
      add_timestamps_with_timezone(t)
    end
    add_index :reimbursements, [:team_id, :expense_id], unique: true
    add_index :reimbursements, [:team_id, :status, :created_at]
    add_check_constraint :reimbursements, "amount > 0", name: "reimbursements_amount_positive"
    add_check_constraint :reimbursements, "currency ~ '^[A-Z]{3}$'", name: "reimbursements_currency_format"
    add_check_constraint :reimbursements,
      "status IN ('pending', 'processing', 'paid', 'failed', 'cancelled')",
      name: "reimbursements_status_valid"
    add_check_constraint :reimbursements,
      "(status = 'paid' AND paid_at IS NOT NULL) OR (status <> 'paid' AND paid_at IS NULL)",
      name: "reimbursements_paid_timestamp_valid"
    add_check_constraint :reimbursements,
      "(status = 'failed' AND failure_reason IS NOT NULL AND btrim(failure_reason) <> '') OR (status <> 'failed' AND failure_reason IS NULL)",
      name: "reimbursements_failure_reason_valid"

    create_table :audit_logs do |t|
      t.references :team, null: false, index: false, foreign_key: { on_delete: :restrict }
      t.bigint :expense_id, null: false
      t.bigint :actor_membership_id
      t.string :actor_type, null: false
      t.string :category, null: false
      t.string :event_type, null: false
      t.jsonb :change_data, null: false, default: {}
      t.string :request_id
      t.column :created_at, "timestamp with time zone", null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :audit_logs, [:team_id, :expense_id, :created_at, :id], name: "index_audit_logs_on_expense_history"
    add_check_constraint :audit_logs,
      "(category = 'crud' AND event_type IN ('create', 'update', 'delete')) OR " \
      "(category = 'workflow' AND event_type IN ('submitted', 'approved', 'rejected', 'reimbursement_paid', 'import_accepted'))",
      name: "audit_logs_category_event_valid"
    add_check_constraint :audit_logs,
      "(actor_type = 'user' AND actor_membership_id IS NOT NULL) OR " \
      "(actor_type = 'system' AND actor_membership_id IS NULL)",
      name: "audit_logs_actor_valid"

    add_same_team_foreign_keys
  end

  def down
    remove_same_team_foreign_keys
    drop_table :audit_logs
    drop_table :reimbursements
    drop_table :expense_approvals
    drop_table :expenses
    drop_table :imported_transactions
    drop_table :imports
    drop_table :team_memberships
    drop_table :teams
    drop_table :auth_sessions
    drop_table :users
  end

  private

  def add_timestamps_with_timezone(table_definition, updated: true)
    table_definition.column :created_at, "timestamp with time zone", null: false, default: -> { "CURRENT_TIMESTAMP" }
    table_definition.column :updated_at, "timestamp with time zone", null: false, default: -> { "CURRENT_TIMESTAMP" } if updated
  end

  def add_same_team_foreign_keys
    execute <<~SQL
      ALTER TABLE imports
        ADD CONSTRAINT fk_imports_requester_same_team
        FOREIGN KEY (team_id, requested_by_membership_id)
        REFERENCES team_memberships (team_id, id) ON DELETE RESTRICT;

      ALTER TABLE imported_transactions
        ADD CONSTRAINT fk_imported_transactions_import_same_team
        FOREIGN KEY (team_id, import_id)
        REFERENCES imports (team_id, id) ON DELETE RESTRICT;
      ALTER TABLE imported_transactions
        ADD CONSTRAINT fk_imported_transactions_reviewer_same_team
        FOREIGN KEY (team_id, reviewed_by_membership_id)
        REFERENCES team_memberships (team_id, id) ON DELETE RESTRICT;

      ALTER TABLE expenses
        ADD CONSTRAINT fk_expenses_creator_same_team
        FOREIGN KEY (team_id, creator_membership_id)
        REFERENCES team_memberships (team_id, id) ON DELETE RESTRICT;
      ALTER TABLE expenses
        ADD CONSTRAINT fk_expenses_member_same_team
        FOREIGN KEY (team_id, member_membership_id)
        REFERENCES team_memberships (team_id, id) ON DELETE RESTRICT;
      ALTER TABLE expenses
        ADD CONSTRAINT fk_expenses_imported_transaction_same_team
        FOREIGN KEY (team_id, imported_transaction_id)
        REFERENCES imported_transactions (team_id, id) ON DELETE RESTRICT;

      ALTER TABLE expense_approvals
        ADD CONSTRAINT fk_expense_approvals_expense_same_team
        FOREIGN KEY (team_id, expense_id)
        REFERENCES expenses (team_id, id) ON DELETE RESTRICT;
      ALTER TABLE expense_approvals
        ADD CONSTRAINT fk_expense_approvals_approver_same_team
        FOREIGN KEY (team_id, approver_membership_id)
        REFERENCES team_memberships (team_id, id) ON DELETE RESTRICT;

      ALTER TABLE reimbursements
        ADD CONSTRAINT fk_reimbursements_expense_same_team
        FOREIGN KEY (team_id, expense_id)
        REFERENCES expenses (team_id, id) ON DELETE RESTRICT;
      ALTER TABLE reimbursements
        ADD CONSTRAINT fk_reimbursements_initiator_same_team
        FOREIGN KEY (team_id, initiated_by_membership_id)
        REFERENCES team_memberships (team_id, id) ON DELETE RESTRICT;

      ALTER TABLE audit_logs
        ADD CONSTRAINT fk_audit_logs_expense_same_team
        FOREIGN KEY (team_id, expense_id)
        REFERENCES expenses (team_id, id) ON DELETE RESTRICT;
      ALTER TABLE audit_logs
        ADD CONSTRAINT fk_audit_logs_actor_same_team
        FOREIGN KEY (team_id, actor_membership_id)
        REFERENCES team_memberships (team_id, id) ON DELETE RESTRICT;
    SQL
  end

  def remove_same_team_foreign_keys
    execute <<~SQL
      ALTER TABLE audit_logs DROP CONSTRAINT fk_audit_logs_actor_same_team;
      ALTER TABLE audit_logs DROP CONSTRAINT fk_audit_logs_expense_same_team;
      ALTER TABLE reimbursements DROP CONSTRAINT fk_reimbursements_initiator_same_team;
      ALTER TABLE reimbursements DROP CONSTRAINT fk_reimbursements_expense_same_team;
      ALTER TABLE expense_approvals DROP CONSTRAINT fk_expense_approvals_approver_same_team;
      ALTER TABLE expense_approvals DROP CONSTRAINT fk_expense_approvals_expense_same_team;
      ALTER TABLE expenses DROP CONSTRAINT fk_expenses_imported_transaction_same_team;
      ALTER TABLE expenses DROP CONSTRAINT fk_expenses_member_same_team;
      ALTER TABLE expenses DROP CONSTRAINT fk_expenses_creator_same_team;
      ALTER TABLE imported_transactions DROP CONSTRAINT fk_imported_transactions_reviewer_same_team;
      ALTER TABLE imported_transactions DROP CONSTRAINT fk_imported_transactions_import_same_team;
      ALTER TABLE imports DROP CONSTRAINT fk_imports_requester_same_team;
    SQL
  end
end
