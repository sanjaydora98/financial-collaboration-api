require "rails_helper"

RSpec.describe "Foundation models" do
  def create_user(email = "person@example.com")
    User.create!(email: email, name: "Test Person", password: "password123")
  end

  def create_team_and_creator(email = "creator@example.com")
    user = create_user(email)
    team = Team.create!(name: "Test Team", slug: "team-#{SecureRandom.hex(4)}", creator: user)
    membership = TeamMembership.create!(team: team, user: user, role: "creator")
    [team, membership]
  end

  def create_import(team, requester, idempotency_key: SecureRandom.hex(8))
    Import.create!(
      team: team,
      requested_by_membership: requester,
      provider: "bank",
      idempotency_key: idempotency_key
    )
  end

  def create_imported_transaction(team, import, attributes = {})
    ImportedTransaction.create!({
      team: team,
      import: import,
      provider: "bank",
      external_account_ref: "account-1",
      external_transaction_id: SecureRandom.hex(8),
      amount: 12.50,
      currency: "USD",
      merchant: "Coffee Shop",
      transaction_date: Date.current
    }.merge(attributes))
  end

  def create_expense(team, membership, attributes = {})
    Expense.create!({
      team: team,
      creator_membership: membership,
      member_membership: membership,
      amount: 12.50,
      currency: "USD",
      merchant: "Coffee Shop",
      incurred_on: Date.current
    }.merge(attributes))
  end

  describe "associations" do
    it "connects users, teams, memberships, expenses, approvals, reimbursements, audits, and imports" do
      expect(User.reflect_on_association(:team_memberships).macro).to eq(:has_many)
      expect(Team.reflect_on_association(:team_memberships).macro).to eq(:has_many)
      expect(TeamMembership.reflect_on_association(:team).macro).to eq(:belongs_to)
      expect(Expense.reflect_on_association(:creator_membership).macro).to eq(:belongs_to)
      expect(Expense.reflect_on_association(:member_membership).macro).to eq(:belongs_to)
      expect(Expense.reflect_on_association(:expense_approvals).macro).to eq(:has_many)
      expect(ExpenseApproval.reflect_on_association(:approver_membership).macro).to eq(:belongs_to)
      expect(Expense.reflect_on_association(:reimbursement).macro).to eq(:has_one)
      expect(Expense.reflect_on_association(:audit_logs).macro).to eq(:has_many)
      expect(Import.reflect_on_association(:imported_transactions).macro).to eq(:has_many)
      expect(ImportedTransaction.reflect_on_association(:expense).macro).to eq(:has_one)
      expect(AuthSession.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
  end

  describe "validations and enums" do
    it "normalizes user email and validates password-backed users" do
      user = User.create!(email: "  PERSON@EXAMPLE.COM ", name: "Person", password: "password123")
      expect(user.email).to eq("person@example.com")
      expect(user.authenticate("password123")).to eq(user)
      expect(User.new(email: "person@example.com", name: "Other", password: "password123")).not_to be_valid
    end

    it "enforces the approved membership stage rule in the model" do
      team, = create_team_and_creator
      user = create_user("admin@example.com")
      expect(TeamMembership.new(team: team, user: user, role: "admin", approval_stage: "manager")).to be_valid
      expect(TeamMembership.new(team: team, user: user, role: "admin")).to be_valid
      expect(TeamMembership.new(team: team, user: user, role: "approver", approval_stage: "finance")).to be_valid
      expect(TeamMembership.new(team: team, user: user, role: "creator", approval_stage: "manager")).not_to be_valid
      expect(TeamMembership.new(team: team, user: user, role: "viewer", approval_stage: "finance")).not_to be_valid
    end

    it "exposes string-backed status and role enums" do
      expect(Expense.statuses.keys).to eq(Expense::STATUSES)
      expect(Expense.new(status: "draft")).to be_draft
      expect { Expense.new(status: "unknown") }.to raise_error(ArgumentError)
      expect(TeamMembership.new(role: "admin")).to be_admin
      expect(ExpenseApproval.new(status: "pending")).to be_pending
      expect(Reimbursement.new(status: "paid")).to be_paid
      expect(Import.new(status: "queued")).to be_queued
      expect(ImportedTransaction.new(status: "pending")).to be_pending
    end

    it "validates positive amounts and supported currency format" do
      team, membership = create_team_and_creator
      expect(Expense.new(team: team, creator_membership: membership, member_membership: membership,
        amount: 0, currency: "usd", merchant: "Shop", incurred_on: Date.current)).not_to be_valid
    end
  end

  describe "expense audit callbacks" do
    it "writes create, update, and logical-delete CRUD audits" do
      team, membership = create_team_and_creator
      expense = nil

      expect { expense = create_expense(team, membership) }.to change(AuditLog, :count).by(1)
      expect(expense.audit_logs.last).to have_attributes(category: "crud", event_type: "create", actor_type: "system")
      expect(expense.audit_logs.last.change_data.dig("after")).to include("amount", "merchant")
      expect(AuditLog.column_names).not_to include("changes")

      expect { expense.update!(description: "Updated") }.to change(AuditLog, :count).by(1)
      expect(expense.audit_logs.last.event_type).to eq("update")

      expect { expense.update!(deleted_at: Time.current) }.to change(AuditLog, :count).by(1)
      expect(expense.audit_logs.last.event_type).to eq("delete")
    end

    it "rolls back the expense write if its audit actor violates tenant integrity" do
      team, membership = create_team_and_creator
      other_team, other_membership = create_team_and_creator("other@example.com")
      expense = Expense.new(
        team: team,
        creator_membership: membership,
        member_membership: membership,
        audit_actor_membership_id: other_membership.id,
        amount: 12.50,
        currency: "USD",
        merchant: "Coffee Shop",
        incurred_on: Date.current
      )

      expect { expense.save! }.to raise_error(ActiveRecord::InvalidForeignKey)
      expect(Expense.where(team: team).count).to eq(0)
      expect(other_team).to be_persisted
    end

    it "keeps audit rows append-only" do
      team, membership = create_team_and_creator
      audit_log = create_expense(team, membership).audit_logs.last

      expect { audit_log.update!(request_id: "modified") }.to raise_error(ActiveRecord::RecordNotSaved)
      expect { audit_log.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    end
  end

  describe "PostgreSQL uniqueness and tenant constraints" do
    it "allows only one membership per user and team" do
      team, membership = create_team_and_creator
      expect {
        TeamMembership.create!(team: team, user: membership.user, role: "viewer")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows one active Manager slot across approver and staged-admin memberships" do
      team, = create_team_and_creator
      admin_user = create_user("manager-admin@example.com")
      TeamMembership.create!(team: team, user: admin_user, role: "admin", approval_stage: "manager")
      approver_user = create_user("manager-approver@example.com")

      expect {
        TeamMembership.create!(team: team, user: approver_user, role: "approver", approval_stage: "manager")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects an approver membership without an approval stage at the database layer" do
      team, = create_team_and_creator
      user = create_user("unstaged-approver@example.com")

      expect {
        TeamMembership.insert_all!([{ team_id: team.id, user_id: user.id, role: "approver", approval_stage: nil }])
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "enforces approval assignment uniqueness" do
      team, creator = create_team_and_creator
      approver_user = create_user("approver@example.com")
      approver = TeamMembership.create!(team: team, user: approver_user, role: "approver", approval_stage: "manager")
      expense = create_expense(team, creator)
      attributes = { team: team, expense: expense, step: 1, stage: "manager", approver_membership: approver, status: "pending" }
      ExpenseApproval.create!(attributes)

      expect { ExpenseApproval.create!(attributes) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects a database approval decision without its required rejection reason" do
      team, creator = create_team_and_creator
      approver = TeamMembership.create!(team: team, user: create_user("reason-approver@example.com"), role: "approver", approval_stage: "manager")
      expense = create_expense(team, creator)

      expect {
        ExpenseApproval.insert_all!([{
          team_id: team.id,
          expense_id: expense.id,
          step: 1,
          stage: "manager",
          approver_membership_id: approver.id,
          status: "rejected",
          acted_at: Time.current,
          rejection_reason: nil
        }])
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects a failed reimbursement without its required failure reason" do
      team, creator = create_team_and_creator
      expense = create_expense(team, creator)

      expect {
        Reimbursement.insert_all!([{
          team_id: team.id,
          expense_id: expense.id,
          initiated_by_membership_id: creator.id,
          amount: 12.50,
          currency: "USD",
          status: "failed",
          failure_reason: nil
        }])
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects an imported transaction decision without its required rejection reason" do
      team, requester = create_team_and_creator
      import = create_import(team, requester)

      expect {
        ImportedTransaction.insert_all!([{
          team_id: team.id,
          import_id: import.id,
          provider: "bank",
          external_account_ref: "account-1",
          external_transaction_id: "rejected-txn",
          amount: 12.50,
          currency: "USD",
          merchant: "Coffee Shop",
          transaction_date: Date.current,
          status: "rejected",
          reviewed_by_membership_id: requester.id,
          reviewed_at: Time.current,
          rejection_reason: nil
        }])
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "deduplicates import requests by team, provider, and idempotency key" do
      team, requester = create_team_and_creator
      create_import(team, requester, idempotency_key: "request-1")

      expect { create_import(team, requester, idempotency_key: "request-1") }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "deduplicates external transactions across import batches" do
      team, requester = create_team_and_creator
      first_import = create_import(team, requester, idempotency_key: "batch-1")
      second_import = create_import(team, requester, idempotency_key: "batch-2")
      key = { external_account_ref: "account-1", external_transaction_id: "txn-1" }
      create_imported_transaction(team, first_import, key)

      expect { create_imported_transaction(team, second_import, key) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows at most one expense per imported transaction" do
      team, creator = create_team_and_creator
      requester = TeamMembership.create!(team: team, user: create_user("requester@example.com"), role: "creator")
      imported_transaction = create_imported_transaction(team, create_import(team, requester))
      create_expense(team, creator, imported_transaction: imported_transaction)

      expect {
        create_expense(team, creator, imported_transaction: imported_transaction)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects references to a membership from another team" do
      team, creator = create_team_and_creator
      other_team, other_membership = create_team_and_creator("other-member@example.com")
      expense = create_expense(team, creator)

      expect {
        expense.update_columns(member_membership_id: other_membership.id)
      }.to raise_error(ActiveRecord::InvalidForeignKey)
      expect(other_team).to be_persisted
    end

    it "enforces database checks even when model validations are bypassed" do
      team, creator = create_team_and_creator
      expense = create_expense(team, creator)

      expect { expense.update_columns(currency: "usd") }.to raise_error(ActiveRecord::StatementInvalid)
      expect { expense.update_columns(amount: 0) }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end