require "rails_helper"

RSpec.describe "Expenses API", type: :request do
  def create_user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  def headers_for(user)
    token = Authentication::SessionIssuer.call(user: user).token
    { "Authorization" => "Bearer #{token}" }
  end

  def create_team(user, slug: SecureRandom.hex(5))
    Teams::Create.call(user: user, attributes: { name: "Team #{slug}", slug: slug }).first
  end

  def promote_to_admin(team, user)
    # The team creator is already admin as of Teams::Create; this helper is
    # kept so existing call sites read clearly, but no promotion is needed.
    team.team_memberships.find_by!(user: user, role: "admin")
  end

  def expense_params(attributes = {})
    {
      amount: "42.50",
      currency: "USD",
      merchant: "Office Supply",
      description: "Notebooks",
      category: "Supplies",
      incurred_on: Date.current.to_s
    }.merge(attributes)
  end

  def post_expense(team, user, attributes = {})
    post "/teams/#{team.id}/expenses",
      params: { expense: expense_params(attributes) },
      headers: headers_for(user), as: :json
  end

  def json
    JSON.parse(response.body)
  end

  describe "creation" do
    it "allows a member to create an expense attributed to themselves with one audit row" do
      user = create_user("self-expense@example.com")
      team = create_team(user)

      expect { post_expense(team, user) }.to change(Expense, :count).by(1).and change(AuditLog, :count).by(1)

      expense = Expense.last
      membership = team.team_memberships.find_by!(user: user)
      expect(response).to have_http_status(:created)
      expect(expense).to have_attributes(
        creator_membership_id: membership.id,
        member_membership_id: membership.id,
        status: "draft",
        lock_version: 0
      )
      expect(json.dig("expense", "creator_membership_id")).to eq(membership.id)
      expect(expense.audit_logs.last).to have_attributes(category: "crud", event_type: "create")
    end

    it "allows an admin to create an expense for themselves or another active team member" do
      admin = create_user("admin-expense@example.com")
      team = create_team(admin)
      admin_membership = promote_to_admin(team, admin)
      other_user = create_user("attributed-member@example.com")
      other_membership = TeamMembership.create!(team: team, user: other_user, role: "viewer")

      post_expense(team, admin, member_membership_id: admin_membership.id)
      expect(response).to have_http_status(:created)
      expect(Expense.last).to have_attributes(creator_membership_id: admin_membership.id, member_membership_id: admin_membership.id)

      post_expense(team, admin, member_membership_id: other_membership.id)
      expect(response).to have_http_status(:created)
      expect(Expense.last).to have_attributes(creator_membership_id: admin_membership.id, member_membership_id: other_membership.id)
    end

    it "prevents a non-admin from creating an expense for another member" do
      owner = create_user("non-admin-expense-owner@example.com")
      team = create_team(owner)
      creator = create_user("non-admin-expense@example.com")
      TeamMembership.create!(team: team, user: creator, role: "creator")
      target = TeamMembership.create!(team: team, user: create_user("non-admin-target@example.com"), role: "viewer")

      expect { post_expense(team, creator, member_membership_id: target.id) }.not_to change(Expense, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects cross-team or inactive attributed memberships without creating an expense" do
      admin = create_user("membership-target-admin@example.com")
      team = create_team(admin)
      promote_to_admin(team, admin)
      other_team = create_team(create_user("different-team@example.com"))
      foreign_membership = other_team.team_memberships.first
      inactive_membership = TeamMembership.create!(team: team, user: create_user("inactive-attributed@example.com"), role: "viewer", active: false)

      expect { post_expense(team, admin, member_membership_id: foreign_membership.id) }.not_to change(Expense, :count)
      expect(response).to have_http_status(:not_found)

      expect { post_expense(team, admin, member_membership_id: inactive_membership.id) }.not_to change(Expense, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "rejects invalid amounts and currencies" do
      user = create_user("invalid-expense@example.com")
      team = create_team(user)

      post_expense(team, user, amount: "0", currency: "usd")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Expense.count).to eq(0)
      expect(AuditLog.count).to eq(0)
    end

    it "forces new expenses to draft and ignores client-supplied protected fields" do
      user = create_user("forced-draft@example.com")
      team = create_team(user)
      membership = team.team_memberships.find_by!(user: user)

      post "/teams/#{team.id}/expenses", params: {
        expense: expense_params(status: "approved", team_id: team.id + 100, creator_membership_id: team.team_memberships.first.id + 100,
          member_membership_id: membership.id, lock_version: 100)
      }, headers: headers_for(user), as: :json

      expect(response).to have_http_status(:created)
      expect(Expense.last).to have_attributes(status: "draft", team_id: team.id, creator_membership_id: membership.id, lock_version: 0)
    end

    it "rolls back the expense insert when its create audit fails" do
      user = create_user("audit-rollback@example.com")
      team = create_team(user)
      allow_any_instance_of(Expense).to receive(:record_crud_audit).and_raise(ActiveRecord::RecordNotSaved)

      expect { post_expense(team, user) }.not_to change(Expense, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(AuditLog.count).to eq(0)
    end
  end

  describe "reading" do
    it "lists and shows permitted team expenses but hides other creators' expenses from a creator" do
      owner = create_user("expense-owner-admin@example.com")
      team = create_team(owner)
      creator = create_user("expense-owner@example.com")
      own_membership = TeamMembership.create!(team: team, user: creator, role: "creator")
      other_creator = create_user("expense-other-creator@example.com")
      other_membership = TeamMembership.create!(team: team, user: other_creator, role: "creator")
      own_expense = Expense.create!(team: team, creator_membership: own_membership, member_membership: own_membership,
        amount: 10, currency: "USD", merchant: "Own", incurred_on: Date.current)
      other_expense = Expense.create!(team: team, creator_membership: other_membership, member_membership: other_membership,
        amount: 20, currency: "USD", merchant: "Other", incurred_on: Date.current)

      get "/teams/#{team.id}/expenses", headers: headers_for(creator)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("expenses").map { |item| item.fetch("id") }).to eq([own_expense.id])

      get "/teams/#{team.id}/expenses/#{own_expense.id}", headers: headers_for(creator)
      expect(response).to have_http_status(:ok)

      get "/teams/#{team.id}/expenses/#{other_expense.id}", headers: headers_for(creator)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 200 consistently for repeated index requests (regression for stray debugger calls)" do
      owner = create_user("expense-index-regression@example.com")
      team = create_team(owner)
      membership = team.team_memberships.find_by!(user: owner)
      Expense.create!(team: team, creator_membership: membership, member_membership: membership,
        amount: 10, currency: "USD", merchant: "Own", incurred_on: Date.current)

      3.times do
        get "/teams/#{team.id}/expenses", headers: headers_for(owner)
        expect(response).to have_http_status(:ok)
        expect(json).not_to have_key("error")
      end
    end

    it "returns 404 for cross-team and non-member expense access" do
      owner = create_user("expense-team-owner@example.com")
      team = create_team(owner)
      membership = team.team_memberships.find_by!(user: owner)
      expense = Expense.create!(team: team, creator_membership: membership, member_membership: membership,
        amount: 10, currency: "USD", merchant: "Private", incurred_on: Date.current)
      other_team = create_team(create_user("expense-other-team-owner@example.com"))
      outsider = create_user("expense-outsider@example.com")

      get "/teams/#{other_team.id}/expenses/#{expense.id}", headers: headers_for(user_from_team(owner))
      expect(response).to have_http_status(:not_found)

      get "/teams/#{team.id}/expenses", headers: headers_for(outsider)
      expect(response).to have_http_status(:not_found)

      patch "/teams/#{team.id}/expenses/#{expense.id}", params: { expense: { description: "cross-team write" }, lock_version: 0 }, headers: headers_for(outsider), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "excludes logically deleted expenses from list and show" do
      owner = create_user("deleted-expense-owner@example.com")
      team = create_team(owner)
      promote_to_admin(team, owner)
      post_expense(team, owner)
      expense_id = json.dig("expense", "id")
      lock_version = json.dig("expense", "lock_version")
      delete "/teams/#{team.id}/expenses/#{expense_id}", params: { lock_version: lock_version }, headers: headers_for(owner), as: :json

      get "/teams/#{team.id}/expenses", headers: headers_for(owner)
      expect(json.fetch("expenses")).to be_empty
      get "/teams/#{team.id}/expenses/#{expense_id}", headers: headers_for(owner)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "updates and optimistic locking" do
    it "allows a creator to update their own draft and increments lock_version" do
      owner = create_user("draft-update@example.com")
      team = create_team(owner)
      post_expense(team, owner)
      expense_id = json.dig("expense", "id")
      version = json.dig("expense", "lock_version")

      patch "/teams/#{team.id}/expenses/#{expense_id}", params: { expense: { description: "Updated receipt" }, lock_version: version }, headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("expense", "description")).to eq("Updated receipt")
      expect(json.dig("expense", "lock_version")).to eq(version + 1)
    end

    it "denies creators editing another user's expense and approvers editing team expenses" do
      owner = create_user("protected-expense-owner@example.com")
      team = create_team(owner)
      owner_membership = team.team_memberships.find_by!(user: owner)
      expense = Expense.create!(team: team, creator_membership: owner_membership, member_membership: owner_membership,
        amount: 10, currency: "USD", merchant: "Protected", incurred_on: Date.current)
      other_creator = create_user("protected-expense-other@example.com")
      TeamMembership.create!(team: team, user: other_creator, role: "creator")
      approver = create_user("protected-expense-approver@example.com")
      TeamMembership.create!(team: team, user: approver, role: "approver", approval_stage: "manager")

      patch "/teams/#{team.id}/expenses/#{expense.id}", params: { expense: { description: "no" }, lock_version: 0 }, headers: headers_for(other_creator), as: :json
      expect(response).to have_http_status(:forbidden)

      patch "/teams/#{team.id}/expenses/#{expense.id}", params: { expense: { description: "no" }, lock_version: 0 }, headers: headers_for(approver), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "allows an admin to update another member's draft" do
      admin = create_user("admin-update@example.com")
      team = create_team(admin)
      promote_to_admin(team, admin)
      member = TeamMembership.create!(team: team, user: create_user("admin-update-member@example.com"), role: "viewer")
      expense = Expense.create!(team: team, creator_membership: member, member_membership: member,
        amount: 10, currency: "USD", merchant: "Admin editable", incurred_on: Date.current)

      patch "/teams/#{team.id}/expenses/#{expense.id}", params: { expense: { description: "Admin edit" }, lock_version: 0 }, headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(expense.reload.description).to eq("Admin edit")
    end

    it "rejects modifications outside draft state and failed updates add no audit row" do
      owner = create_user("non-draft-update@example.com")
      team = create_team(owner)
      post_expense(team, owner)
      expense = Expense.find(response_json_id)
      expense.update!(status: "submitted")
      audits_before = AuditLog.count

      patch "/teams/#{team.id}/expenses/#{expense.id}", params: { expense: { description: "cannot edit" }, lock_version: expense.lock_version }, headers: headers_for(owner), as: :json
      expect(response).to have_http_status(:forbidden)

      expense.update_column(:status, "draft")
      current_version = expense.reload.lock_version
      patch "/teams/#{team.id}/expenses/#{expense.id}", params: { expense: { amount: 0 }, lock_version: current_version }, headers: headers_for(owner), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(AuditLog.count).to eq(audits_before)
      expect(expense.reload.amount).to eq(BigDecimal("42.50"))
    end

    it "returns 409 for a stale client version and preserves the newer value" do
      owner = create_user("stale-client@example.com")
      team = create_team(owner)
      post_expense(team, owner)
      expense_id = json.dig("expense", "id")
      stale_version = json.dig("expense", "lock_version")

      patch "/teams/#{team.id}/expenses/#{expense_id}", params: { expense: { description: "first write" }, lock_version: stale_version }, headers: headers_for(owner), as: :json
      expect(response).to have_http_status(:ok)

      patch "/teams/#{team.id}/expenses/#{expense_id}", params: { expense: { description: "stale overwrite" }, lock_version: stale_version }, headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json.dig("error", "current_lock_version")).to eq(stale_version + 1)
      expect(Expense.find(expense_id).description).to eq("first write")
    end
  end

  describe "logical deletion and auditing" do
    it "allows an owner to logically delete a draft and keeps the row and delete audit" do
      owner = create_user("logical-delete@example.com")
      team = create_team(owner)
      post_expense(team, owner)
      expense_id = json.dig("expense", "id")
      version = json.dig("expense", "lock_version")
      audits_before = AuditLog.count

      delete "/teams/#{team.id}/expenses/#{expense_id}", params: { lock_version: version }, headers: headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(Expense.exists?(expense_id)).to be(true)
      expect(Expense.find(expense_id).deleted_at).to be_present
      expect(AuditLog.count).to eq(audits_before + 1)
      expect(Expense.find(expense_id).audit_logs.last.event_type).to eq("delete")
    end

    it "allows an admin to logically delete another member's draft" do
      admin = create_user("admin-delete@example.com")
      team = create_team(admin)
      promote_to_admin(team, admin)
      member = TeamMembership.create!(team: team, user: create_user("admin-delete-member@example.com"), role: "viewer")
      expense = Expense.create!(team: team, creator_membership: member, member_membership: member,
        amount: 10, currency: "USD", merchant: "Admin deletion", incurred_on: Date.current)

      delete "/teams/#{team.id}/expenses/#{expense.id}", params: { lock_version: 0 }, headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(expense.reload.deleted_at).to be_present
      expect(expense.audit_logs.last.event_type).to eq("delete")
    end

    it "denies deleting another creator's expense and prevents physical destroy" do
      owner = create_user("delete-owner@example.com")
      team = create_team(owner)
      owner_membership = team.team_memberships.find_by!(user: owner)
      expense = Expense.create!(team: team, creator_membership: owner_membership, member_membership: owner_membership,
        amount: 10, currency: "USD", merchant: "Keep", incurred_on: Date.current)
      other = create_user("delete-other@example.com")
      TeamMembership.create!(team: team, user: other, role: "creator")

      delete "/teams/#{team.id}/expenses/#{expense.id}", params: { lock_version: 0 }, headers: headers_for(other), as: :json
      expect(response).to have_http_status(:forbidden)
      expect { expense.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
      expect(Expense.exists?(expense.id)).to be(true)
    end

    it "records before/after JSON audit payloads without authentication secrets" do
      owner = create_user("audit-payload@example.com")
      team = create_team(owner)
      post_expense(team, owner)
      expense_id = json.dig("expense", "id")
      audit = Expense.find(expense_id).audit_logs.last
      expect(audit.change_data).to include("before" => {}, "after" => include("merchant" => "Office Supply"))
      expect(audit.change_data.to_json).not_to include("password", "token", "digest")

      patch "/teams/#{team.id}/expenses/#{expense_id}", params: { expense: { description: "Changed" }, lock_version: 0 }, headers: headers_for(owner), as: :json
      update_audit = Expense.find(expense_id).audit_logs.order(:id).last
      expect(update_audit.change_data).to eq(
        "before" => { "description" => "Notebooks" },
        "after" => { "description" => "Changed" }
      )
    end
  end

  private

  def user_from_team(user)
    user
  end

  def response_json_id
    JSON.parse(response.body).dig("expense", "id")
  end
end