require "rails_helper"

RSpec.describe "Reimbursements API", type: :request do
  before { setup_reimbursement_context }

  def create_user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  def headers_for(user)
    token = Authentication::SessionIssuer.call(user: user).token
    { "Authorization" => "Bearer #{token}" }
  end

  def create_team(user)
    Teams::Create.call(user: user, attributes: { name: "Reimbursement team", slug: "reimbursement-#{SecureRandom.hex(4)}" }).first
  end

  def setup_reimbursement_context
    @creator = create_user("reimbursement-creator-#{SecureRandom.hex(4)}@example.com")
    @team = create_team(@creator)
    @creator_membership = @team.team_memberships.find_by!(user: @creator)
    @other_creator = create_user("reimbursement-other-#{SecureRandom.hex(4)}@example.com")
    @other_creator_membership = TeamMembership.create!(team: @team, user: @other_creator, role: "creator")
    @admin = create_user("reimbursement-admin-#{SecureRandom.hex(4)}@example.com")
    @admin_membership = TeamMembership.create!(team: @team, user: @admin, role: "admin")
    @viewer = create_user("reimbursement-viewer-#{SecureRandom.hex(4)}@example.com")
    @viewer_membership = TeamMembership.create!(team: @team, user: @viewer, role: "viewer")
    @approver = create_user("reimbursement-approver-#{SecureRandom.hex(4)}@example.com")
    @approver_membership = TeamMembership.create!(team: @team, user: @approver, role: "approver", approval_stage: "manager")
    @expense = create_expense(@creator_membership, status: "approved")
  end

  def create_expense(membership, status: "approved", deleted_at: nil)
    Expense.create!(
      team: @team,
      creator_membership: membership,
      member_membership: membership,
      amount: 86.40,
      currency: "USD",
      merchant: "Train ticket",
      incurred_on: Date.current,
      status: status,
      deleted_at: deleted_at
    )
  end

  def post_reimbursement(expense: @expense, team: @team, user: @creator)
    post "/teams/#{team.id}/expenses/#{expense.id}/reimbursement", headers: headers_for(user), as: :json
  end

  def json
    JSON.parse(response.body)
  end

  it "allows a creator to reimburse their own approved expense for the full amount" do
    expect { post_reimbursement }.to change(Reimbursement, :count).by(1)

    expect(response).to have_http_status(:created)
    reimbursement = Reimbursement.last
    expect(reimbursement).to have_attributes(
      initiated_by_membership_id: @creator_membership.id,
      amount: BigDecimal("86.40"),
      currency: "USD",
      status: "paid"
    )
    expect(reimbursement.paid_at).to be_present
    expect(@expense.reload.status).to eq("reimbursed")
  end

  it "allows an admin to reimburse any approved non-deleted expense in the team" do
    expense = create_expense(@other_creator_membership)

    post_reimbursement(expense: expense, user: @admin)

    expect(response).to have_http_status(:created)
    expect(Reimbursement.last.initiated_by_membership_id).to eq(@admin_membership.id)
    expect(expense.reload.status).to eq("reimbursed")
  end

  it "denies creators for another creator's expense and denies approvers/viewers" do
    expense = create_expense(@other_creator_membership)

    post_reimbursement(expense: expense, user: @creator)
    expect(response).to have_http_status(:forbidden)

    post_reimbursement(user: @viewer)
    expect(response).to have_http_status(:forbidden)

    post_reimbursement(user: @approver)
    expect(response).to have_http_status(:forbidden)
    expect(Reimbursement.count).to eq(0)
  end

  it "returns 404 for a cross-team expense and an inactive membership" do
    outsider = create_user("reimbursement-outsider@example.com")
    other_team = create_team(outsider)

    post_reimbursement(team: other_team, user: @creator)
    expect(response).to have_http_status(:not_found)

    @creator_membership.update!(active: false)
    post_reimbursement(user: @creator)
    expect(response).to have_http_status(:not_found)
  end

  it "returns 401 when unauthenticated" do
    post "/teams/#{@team.id}/expenses/#{@expense.id}/reimbursement", as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects draft, submitted, rejected, and deleted expenses" do
    ["draft", "submitted", "rejected"].each do |status|
      expense = create_expense(@creator_membership, status: status)
      post_reimbursement(expense: expense)
      expect(response).to have_http_status(:conflict), "expected #{status} expense to conflict"
      expect(expense.reload.status).to eq(status)
    end

    deleted = create_expense(@creator_membership, deleted_at: Time.current)
    post_reimbursement(expense: deleted)
    expect(response).to have_http_status(:conflict)
    expect(deleted.reload.status).to eq("approved")
  end

  it "rejects repeated reimbursement attempts and preserves the existing record" do
    post_reimbursement
    expect(response).to have_http_status(:created)
    reimbursement_id = Reimbursement.last.id

    expect { post_reimbursement }.not_to change(Reimbursement, :count)
    expect(response).to have_http_status(:conflict)
    expect(Reimbursement.last.id).to eq(reimbursement_id)
  end

  it "records initiated and paid workflow audits with before/after states" do
    post_reimbursement

    expect(response).to have_http_status(:created)
    audits = @expense.audit_logs.where(category: "workflow").order(:id)
    expect(audits.pluck(:event_type)).to eq(%w[reimbursement_initiated reimbursement_paid])
    expect(audits.first.change_data).to include(
      "before" => { "expense_status" => "approved", "reimbursement_status" => nil },
      "after" => include("reimbursement_status" => "pending")
    )
    expect(audits.last.change_data).to include(
      "before" => { "expense_status" => "approved", "reimbursement_status" => "pending" },
      "after" => include("expense_status" => "reimbursed", "reimbursement_status" => "paid")
    )
  end

  it "persists a failed simulated settlement without changing expense state" do
    allow(Reimbursements::PaymentSimulator).to receive(:call).and_return(
      Reimbursements::PaymentSimulator::Result.new(status: "failed", failure_reason: "Simulated bank rejection")
    )

    post_reimbursement

    expect(response).to have_http_status(:created)
    expect(Reimbursement.last).to have_attributes(status: "failed", failure_reason: "Simulated bank rejection", paid_at: nil)
    expect(@expense.reload.status).to eq("approved")
    failure_audit = @expense.audit_logs.find_by!(category: "workflow", event_type: "reimbursement_failed")
    expect(failure_audit.change_data.dig("after", "failure_reason")).to eq("Simulated bank rejection")
  end

  it "keeps the audit check and model event allowlist consistent" do
    expect(AuditConstants::WORKFLOW_EVENTS.values).to include(
      "submitted", "approved", "rejected", "reimbursement_paid", "import_accepted",
      "reimbursement_initiated", "reimbursement_failed"
    )

    check = ActiveRecord::Base.connection.check_constraints(:audit_logs).find { |constraint| constraint.name == "audit_logs_category_event_valid" }
    expect(check.expression).to include("reimbursement_initiated", "reimbursement_failed", "reimbursement_paid", "import_accepted")
  end

  it "keeps the database uniqueness constraint as the final duplicate guard" do
    post_reimbursement
    expect(response).to have_http_status(:created)

    expect {
      Reimbursement.create!(
        team: @team,
        expense: @expense,
        initiated_by_membership: @creator_membership,
        amount: @expense.amount,
        currency: @expense.currency,
        status: "pending"
      )
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end