require "rails_helper"

# Focused audit-trail regression coverage: verifies that every workflow event
# (create, update, submit, approve, reject, reimbursement paid) records an
# AuditLog with an identifiable actor, a timestamp, and before/after changed
# field data, as required by the acceptance checklist. Existing specs already
# assert category/event_type and some change_data shapes per-feature; this
# spec consolidates the actor + timestamp assertions across the full
# lifecycle in one place.
RSpec.describe "Audit trail across the expense lifecycle", type: :request do
  def create_user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  def headers_for(user)
    token = Authentication::SessionIssuer.call(user: user).token
    { "Authorization" => "Bearer #{token}" }
  end

  before do
    @creator = create_user("audit-trail-creator-#{SecureRandom.hex(4)}@example.com")
    @team = Teams::Create.call(user: @creator, attributes: { name: "Audit Trail", slug: "audit-trail-#{SecureRandom.hex(4)}" }).first
    @creator_membership = @team.team_memberships.find_by!(user: @creator)
    @manager = create_user("audit-trail-manager-#{SecureRandom.hex(4)}@example.com")
    @manager_membership = TeamMembership.create!(team: @team, user: @manager, role: "approver", approval_stage: "manager")
    @finance = create_user("audit-trail-finance-#{SecureRandom.hex(4)}@example.com")
    @finance_membership = TeamMembership.create!(team: @team, user: @finance, role: "approver", approval_stage: "finance")
  end

  it "records actor, timestamp, and changed fields for create, update, submit, approve, and reimbursement paid" do
    post "/teams/#{@team.id}/expenses",
      params: { expense: { amount: "50.00", currency: "USD", merchant: "Audit Co", description: "Trail", category: "Travel", incurred_on: Date.current.to_s } },
      headers: headers_for(@creator), as: :json
    expense_id = JSON.parse(response.body).dig("expense", "id")
    expense = Expense.find(expense_id)

    create_audit = expense.audit_logs.find_by!(category: "crud", event_type: "create")
    expect(create_audit.actor_type).to eq("user")
    expect(create_audit.actor_membership_id).to eq(@creator_membership.id)
    expect(create_audit.created_at).to be_present
    expect(create_audit.change_data.dig("after", "merchant")).to eq("Audit Co")

    patch "/teams/#{@team.id}/expenses/#{expense_id}",
      params: { expense: { description: "Updated trail" }, lock_version: expense.lock_version },
      headers: headers_for(@creator), as: :json
    update_audit = expense.audit_logs.order(:id).find_by!(category: "crud", event_type: "update")
    expect(update_audit.created_at).to be_present
    expect(update_audit.change_data).to eq("before" => { "description" => "Trail" }, "after" => { "description" => "Updated trail" })

    post "/teams/#{@team.id}/expenses/#{expense_id}/submit", headers: headers_for(@creator), as: :json
    submit_audit = expense.audit_logs.find_by!(category: "workflow", event_type: "submitted")
    expect(submit_audit.actor_membership_id).to eq(@creator_membership.id)
    expect(submit_audit.actor_type).to eq("user")
    expect(submit_audit.created_at).to be_present

    post "/teams/#{@team.id}/expenses/#{expense_id}/approval", params: { approval: { decision: "approve" } }, headers: headers_for(@manager), as: :json
    approve_audit = expense.audit_logs.find_by!(category: "workflow", event_type: "approved")
    expect(approve_audit.actor_membership_id).to eq(@manager_membership.id)
    expect(approve_audit.created_at).to be_present

    post "/teams/#{@team.id}/expenses/#{expense_id}/approval", params: { approval: { decision: "approve" } }, headers: headers_for(@finance), as: :json
    expect(expense.reload.status).to eq("approved")

    post "/teams/#{@team.id}/expenses/#{expense_id}/reimbursement", headers: headers_for(@creator), as: :json
    paid_audit = expense.audit_logs.find_by!(category: "workflow", event_type: "reimbursement_paid")
    expect(paid_audit.actor_membership_id).to eq(@creator_membership.id)
    expect(paid_audit.created_at).to be_present
    expect(paid_audit.change_data.dig("after", "expense_status")).to eq("reimbursed")

    expect(expense.reload.status).to eq("reimbursed")
  end

  it "records actor and rejection reason for a manager rejection" do
    expense = Expense.create!(team: @team, creator_membership: @creator_membership, member_membership: @creator_membership,
      amount: 20, currency: "USD", merchant: "Reject Co", incurred_on: Date.current)
    post "/teams/#{@team.id}/expenses/#{expense.id}/submit", headers: headers_for(@creator), as: :json

    post "/teams/#{@team.id}/expenses/#{expense.id}/approval",
      params: { approval: { decision: "reject", rejection_reason: "Not policy compliant" } },
      headers: headers_for(@manager), as: :json

    reject_audit = expense.audit_logs.find_by!(category: "workflow", event_type: "rejected")
    expect(reject_audit.actor_membership_id).to eq(@manager_membership.id)
    expect(reject_audit.created_at).to be_present
    expect(reject_audit.change_data.dig("after", "rejection_reason")).to eq("Not policy compliant")
    expect(expense.reload.status).to eq("rejected")
  end
end
