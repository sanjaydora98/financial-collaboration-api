require "rails_helper"

RSpec.describe "Expense workflow services" do
  def build_workflow
    creator = User.create!(email: "workflow-service-#{SecureRandom.hex(4)}@example.com", name: "Creator", password: "password123")
    team, creator_membership = Teams::Create.call(user: creator, attributes: { name: "Workflow service", slug: "workflow-service-#{SecureRandom.hex(4)}" })
    manager_user = User.create!(email: "manager-service-#{SecureRandom.hex(4)}@example.com", name: "Manager", password: "password123")
    manager = TeamMembership.create!(team: team, user: manager_user, role: "approver", approval_stage: "manager")
    finance_user = User.create!(email: "finance-service-#{SecureRandom.hex(4)}@example.com", name: "Finance", password: "password123")
    finance = TeamMembership.create!(team: team, user: finance_user, role: "approver", approval_stage: "finance")
    expense = Expense.create!(team: team, creator_membership: creator_membership, member_membership: creator_membership,
      amount: 30, currency: "USD", merchant: "Service workflow", incurred_on: Date.current)
    [creator, team, manager_user, manager, finance_user, finance, expense]
  end

  it "rolls back submission, approval rows, and audit records when workflow audit fails" do
    creator, _team, _manager_user, _manager, _finance_user, _finance, expense = build_workflow
    allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::RecordNotSaved)

    expect { Expenses::Submit.call(expense: expense, user: creator) }.to raise_error(ActiveRecord::RecordNotSaved)
    expect(expense.reload).to have_attributes(status: "draft", submitted_at: nil)
    expect(expense.expense_approvals.count).to eq(0)
    expect(expense.audit_logs.where(category: "workflow").count).to eq(0)
  end

  it "rolls back approval, expense status, and CRUD/workflow audits when decision audit fails" do
    creator, _team, manager_user, _manager, _finance_user, _finance, expense = build_workflow
    Expenses::Submit.call(expense: expense, user: creator)
    allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::RecordNotSaved)

    expect {
      Expenses::Review.call(expense: expense, user: manager_user, decision: "approve")
    }.to raise_error(ActiveRecord::RecordNotSaved)

    expect(expense.reload.status).to eq("submitted")
    expect(expense.expense_approvals.find_by!(stage: "manager").status).to eq("pending")
    expect(expense.expense_approvals.find_by!(stage: "finance").status).to eq("queued")
  end

  it "rejects decisions for deleted expenses even if a pending approval row remains" do
    creator, _team, manager_user, _manager, _finance_user, _finance, expense = build_workflow
    Expenses::Submit.call(expense: expense, user: creator)
    expense.update_column(:deleted_at, Time.current)

    expect {
      Expenses::Review.call(expense: expense, user: manager_user, decision: "approve")
    }.to raise_error(Expenses::WorkflowConflict)
    expect(expense.expense_approvals.find_by!(stage: "manager").status).to eq("pending")
  end

  it "records each workflow audit as append-only" do
    creator, _team, manager_user, _manager, _finance_user, _finance, expense = build_workflow
    Expenses::Submit.call(expense: expense, user: creator)
    submission_audit = expense.audit_logs.find_by!(category: "workflow", event_type: "submitted")

    expect { submission_audit.update!(request_id: "mutated") }.to raise_error(ActiveRecord::RecordNotSaved)
    expect { submission_audit.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)

    Expenses::Review.call(expense: expense, user: manager_user, decision: "reject", rejection_reason: "No receipt")
    rejection_audit = expense.audit_logs.where(category: "workflow", event_type: "rejected").last
    expect(rejection_audit.change_data.dig("before", "expense_status")).to eq("submitted")
    expect(rejection_audit.change_data.dig("after", "expense_status")).to eq("rejected")
    expect(rejection_audit.change_data.dig("after", "rejection_reason")).to eq("No receipt")
  end
end