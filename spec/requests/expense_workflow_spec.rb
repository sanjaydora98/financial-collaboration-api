require "rails_helper"

RSpec.describe "Expense submission and approvals API", type: :request do
  before { create_workflow }

  def create_user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  def headers_for(user)
    token = Authentication::SessionIssuer.call(user: user).token
    { "Authorization" => "Bearer #{token}" }
  end

  def create_workflow
    @creator = create_user("workflow-creator-#{SecureRandom.hex(4)}@example.com")
    @team = Teams::Create.call(user: @creator, attributes: { name: "Workflow", slug: "workflow-#{SecureRandom.hex(4)}" }).first
    @creator_membership = @team.team_memberships.find_by!(user: @creator)
    @manager = create_user("manager-#{SecureRandom.hex(4)}@example.com")
    @manager_membership = TeamMembership.create!(team: @team, user: @manager, role: "approver", approval_stage: "manager")
    @finance = create_user("finance-#{SecureRandom.hex(4)}@example.com")
    @finance_membership = TeamMembership.create!(team: @team, user: @finance, role: "approver", approval_stage: "finance")
    @expense = Expense.create!(
      team: @team,
      creator_membership: @creator_membership,
      member_membership: @creator_membership,
      amount: 30,
      currency: "USD",
      merchant: "Workflow Shop",
      incurred_on: Date.current
    )
  end

  def submit_as(user = @creator)
    post "/teams/#{@team.id}/expenses/#{@expense.id}/submit", headers: headers_for(user), as: :json
  end

  def decide(user, decision, rejection_reason: nil, params: {})
    post "/teams/#{@team.id}/expenses/#{@expense.id}/approval",
      params: { approval: { decision: decision, rejection_reason: rejection_reason }.merge(params) },
      headers: headers_for(user), as: :json
  end

  def response_json
    JSON.parse(response.body)
  end

  it "submits an authorized creator draft with exactly Manager pending and Finance queued" do
    expect { submit_as }.to change(ExpenseApproval, :count).by(2).and change(AuditLog, :count).by(2)

    expect(response).to have_http_status(:ok)
    expect(@expense.reload).to have_attributes(status: "submitted")
    expect(@expense.submitted_at).to be_present
    expect(@expense.expense_approvals.order(:step).pluck(:stage, :status)).to eq([["manager", "pending"], ["finance", "queued"]])
    expect(@expense.audit_logs.where(category: "workflow", event_type: "submitted").count).to eq(1)
    expect(@expense.audit_logs.find_by!(category: "workflow", event_type: "submitted").change_data).to include(
      "before" => { "expense_status" => "draft" },
      "after" => { "expense_status" => "submitted", "manager_approval_status" => "pending", "finance_approval_status" => "queued" }
    )
  end

  it "allows an admin to submit a draft according to the existing ExpensePolicy" do
    @creator_membership.update!(role: "admin")

    submit_as

    expect(response).to have_http_status(:ok)
    expect(@expense.reload.status).to eq("submitted")
  end

  it "denies another creator from submitting this creator's draft" do
    other = create_user("other-workflow-creator@example.com")
    TeamMembership.create!(team: @team, user: other, role: "creator")

    submit_as(other)

    expect(response).to have_http_status(:forbidden)
    expect(@expense.reload.status).to eq("draft")
  end

  it "rejects deleted and already-submitted expenses without duplicating approval rows" do
    @expense.update!(deleted_at: Time.current)
    submit_as
    expect(response).to have_http_status(:conflict)
    expect(@expense.expense_approvals.count).to eq(0)

    @expense.update_column(:deleted_at, nil)
    submit_as
    expect(response).to have_http_status(:ok)
    expect { submit_as }.not_to change(ExpenseApproval, :count)
    expect(response).to have_http_status(:conflict)
    expect(@expense.expense_approvals.count).to eq(2)
  end

  it "returns 422 and rolls back when either stage has no active approver" do
    @finance_membership.update!(active: false)

    expect { submit_as }.not_to change(ExpenseApproval, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(@expense.reload.status).to eq("draft")
    expect(@expense.audit_logs.where(category: "workflow").count).to eq(0)
  end

  it "activates Finance after Manager approval and prevents the Manager from deciding twice" do
    submit_as
    manager_approval = @expense.expense_approvals.find_by!(stage: "manager")

    decide(@manager, "approve", params: { stage: "finance" })

    expect(response).to have_http_status(:ok)
    expect(@expense.reload.status).to eq("submitted")
    expect(manager_approval.reload.status).to eq("approved")
    expect(@expense.expense_approvals.find_by!(stage: "finance").status).to eq("pending")
    expect(@expense.audit_logs.find_by!(category: "workflow", event_type: "approved").change_data.dig("after", "approval_stage")).to eq("manager")

    decide(@manager, "approve")
    expect(response).to have_http_status(:conflict)
  end

  it "rejects at Manager stage and skips Finance without making it actionable" do
    submit_as

    decide(@manager, "reject", rejection_reason: "Missing receipt")

    expect(response).to have_http_status(:ok)
    expect(@expense.reload.status).to eq("rejected")
    expect(@expense.expense_approvals.find_by!(stage: "manager")).to have_attributes(status: "rejected", rejection_reason: "Missing receipt")
    expect(@expense.expense_approvals.find_by!(stage: "finance")).to have_attributes(status: "skipped", acted_at: be_present)
    workflow_audit = @expense.audit_logs.find_by!(category: "workflow", event_type: "rejected")
    expect(workflow_audit.change_data.dig("after", "rejection_reason")).to eq("Missing receipt")

    decide(@finance, "approve")
    expect(response).to have_http_status(:conflict)
    decide(@manager, "reject", rejection_reason: "Again")
    expect(response).to have_http_status(:conflict)
  end

  it "allows Finance to approve or reject only after Manager approval" do
    submit_as
    decide(@finance, "approve")
    expect(response).to have_http_status(:conflict)
    expect(@expense.expense_approvals.find_by!(stage: "manager").status).to eq("pending")

    decide(@manager, "approve")
    expect(response).to have_http_status(:ok)
    decide(@finance, "approve")
    expect(response).to have_http_status(:ok)
    expect(@expense.reload.status).to eq("approved")
    expect(@expense.expense_approvals.find_by!(stage: "finance").status).to eq("approved")
    decide(@finance, "reject", rejection_reason: "Too late")
    expect(response).to have_http_status(:conflict)
  end

  it "rejects at Finance stage and makes the expense terminal" do
    submit_as
    decide(@manager, "approve")
    decide(@finance, "reject", rejection_reason: "Outside policy")

    expect(response).to have_http_status(:ok)
    expect(@expense.reload.status).to eq("rejected")
    expect(@expense.expense_approvals.find_by!(stage: "finance")).to have_attributes(status: "rejected", rejection_reason: "Outside policy")
    decide(@finance, "approve")
    expect(response).to have_http_status(:conflict)
  end

  it "requires a rejection reason and a recognized decision" do
    submit_as
    decide(@manager, "reject")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(@expense.expense_approvals.find_by!(stage: "manager").status).to eq("pending")

    decide(@manager, "maybe")
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "denies normal admins, inactive approvers, cross-team approvers, and non-approvers" do
    submit_as
    admin = create_user("normal-admin-#{SecureRandom.hex(4)}@example.com")
    TeamMembership.create!(team: @team, user: admin, role: "admin")
    decide(admin, "approve")
    expect(response).to have_http_status(:forbidden)

    @manager_membership.update!(active: false)
    decide(@manager, "approve")
    expect(response).to have_http_status(:not_found)
    @manager_membership.update!(active: true)

    other_team_creator = create_user("foreign-approver-owner@example.com")
    other_team = Teams::Create.call(user: other_team_creator, attributes: { name: "Foreign", slug: "foreign-#{SecureRandom.hex(4)}" }).first
    foreign_approver = create_user("foreign-manager@example.com")
    TeamMembership.create!(team: other_team, user: foreign_approver, role: "approver", approval_stage: "manager")
    post "/teams/#{@team.id}/expenses/#{@expense.id}/approval", params: { approval: { decision: "approve" } }, headers: headers_for(foreign_approver), as: :json
    expect(response).to have_http_status(:not_found)

    decide(@creator, "approve")
    expect(response).to have_http_status(:forbidden)
  end

  it "allows stage-assigned admins to review only their assigned approval rows" do
    @manager_membership.update!(role: "admin", approval_stage: "manager")
    @finance_membership.update!(role: "admin", approval_stage: "finance")
    submit_as

    decide(@manager, "approve")
    expect(response).to have_http_status(:ok)
    decide(@finance, "approve")
    expect(response).to have_http_status(:ok)
    expect(@expense.reload.status).to eq("approved")
  end
end