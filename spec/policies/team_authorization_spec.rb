require "rails_helper"

RSpec.describe "Team-scoped authorization policies" do
  def create_user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  def create_team(user, slug)
    Teams::Create.call(user: user, attributes: { name: slug, slug: slug }).first
  end

  def add_membership(team, email, role:, approval_stage: nil, active: true)
    TeamMembership.create!(team: team, user: create_user(email), role: role, approval_stage: approval_stage, active: active)
  end

  def create_expense(team, membership)
    Expense.create!(
      team: team,
      creator_membership: membership,
      member_membership: membership,
      amount: 25,
      currency: "USD",
      merchant: "Stationery",
      incurred_on: Date.current
    )
  end

  describe TeamPolicy do
    it "allows a creator to view their team but not manage membership" do
      creator = create_user("policy-creator@example.com")
      team = create_team(creator, "policy-creator-team")

      policy = described_class.new(creator, team)
      expect(policy.show?).to be(true)
      expect(policy.manage_members?).to be(false)
    end

    it "denies inactive members and users with no membership" do
      owner = create_user("policy-owner@example.com")
      team = create_team(owner, "policy-inactive-team")
      inactive_user = create_user("policy-inactive@example.com")
      TeamMembership.create!(team: team, user: inactive_user, role: "viewer", active: false)
      outsider = create_user("policy-outsider@example.com")

      expect(described_class.new(inactive_user, team).show?).to be(false)
      expect(described_class::Scope.new(inactive_user, Team.all).resolve).not_to include(team)
      expect(described_class.new(outsider, team).show?).to be(false)
    end

    it "scopes teams to active memberships of the authenticated user" do
      user = create_user("policy-scope@example.com")
      own_team = create_team(user, "policy-own-team")
      create_team(create_user("policy-other@example.com"), "policy-other-team")

      expect(described_class::Scope.new(user, Team.all).resolve).to contain_exactly(own_team)
    end
  end

  describe TeamMembershipPolicy do
    it "allows only admins to manage other memberships" do
      owner = create_user("membership-policy-owner@example.com")
      team = create_team(owner, "membership-policy-team")
      creator_membership = team.team_memberships.find_by!(user: owner)
      creator_policy = described_class.new(owner, TeamMembership.new(team: team, user: create_user("target-creator@example.com")))
      expect(creator_policy.create?).to be(false)

      creator_membership.update!(role: "admin")
      target = TeamMembership.new(team: team, user: create_user("target-admin@example.com"))
      admin_policy = described_class.new(owner, target)
      expect(admin_policy.create?).to be(true)
      expect(admin_policy.update?).to be(true)
      expect(admin_policy.destroy?).to be(true)
    end

    it "allows only the team creator to promote their own active creator membership" do
      creator = create_user("bootstrap-policy@example.com")
      team = create_team(creator, "bootstrap-policy-team")
      creator_membership = team.team_memberships.find_by!(user: creator)
      another_user = create_user("bootstrap-policy-other@example.com")
      another_membership = TeamMembership.create!(team: team, user: another_user, role: "viewer")

      expect(described_class.new(creator, creator_membership).bootstrap_admin?).to be(true)
      expect(described_class.new(another_user, another_membership).bootstrap_admin?).to be(false)
    end
  end

  describe ExpensePolicy do
    it "allows creators to read only expenses they created or that belong to them" do
      creator = create_user("expense-policy-creator@example.com")
      team = create_team(creator, "expense-policy-creator-team")
      creator_membership = team.team_memberships.find_by!(user: creator)
      expense = create_expense(team, creator_membership)
      outsider = create_user("expense-policy-outsider@example.com")

      expect(described_class.new(creator, expense).show?).to be(true)
      expect(described_class.new(outsider, expense).show?).to be(false)
      expect(described_class.new(creator, expense).approve?).to be(false)
    end

    it "keeps viewers read-only and approvers limited to their assigned pending stage" do
      owner = create_user("expense-policy-owner@example.com")
      team = create_team(owner, "expense-policy-team")
      expense = create_expense(team, team.team_memberships.find_by!(user: owner))
      viewer = add_membership(team, "expense-policy-viewer@example.com", role: "viewer")
      manager = add_membership(team, "expense-policy-manager@example.com", role: "approver", approval_stage: "manager")
      finance = add_membership(team, "expense-policy-finance@example.com", role: "approver", approval_stage: "finance")
      ExpenseApproval.create!(team: team, expense: expense, step: 1, stage: "manager", approver_membership: manager, status: "pending")

      expect(described_class.new(viewer.user, expense).show?).to be(true)
      expect(described_class.new(viewer.user, expense).approve?).to be(false)
      expect(described_class.new(manager.user, expense).approve?).to be(true)
      expect(described_class.new(manager.user, expense).reject?).to be(true)
      expect(described_class.new(finance.user, expense).approve?).to be(false)
    end

    it "authorizes staged admins only for an assigned approval at their own stage" do
      owner = create_user("staged-policy-owner@example.com")
      team = create_team(owner, "staged-policy-team")
      expense = create_expense(team, team.team_memberships.find_by!(user: owner))
      manager_admin = add_membership(team, "manager-admin@example.com", role: "admin", approval_stage: "manager")
      finance_admin = add_membership(team, "finance-admin@example.com", role: "admin", approval_stage: "finance")
      normal_admin = add_membership(team, "normal-admin@example.com", role: "admin")
      ExpenseApproval.create!(team: team, expense: expense, step: 1, stage: "manager", approver_membership: manager_admin, status: "pending")
      ExpenseApproval.create!(team: team, expense: expense, step: 2, stage: "finance", approver_membership: finance_admin, status: "pending")

      expect(described_class.new(manager_admin.user, expense).approve?).to be(true)
      expect(described_class.new(finance_admin.user, expense).approve?).to be(true)
      expect(described_class.new(normal_admin.user, expense).approve?).to be(false)
    end

    it "does not grant an admin membership authority over another team" do
      admin_user = create_user("foreign-expense-admin@example.com")
      create_team(admin_user, "foreign-expense-team-a")
      owner_b = create_user("foreign-expense-owner@example.com")
      team_b = create_team(owner_b, "foreign-expense-team-b")
      expense_b = create_expense(team_b, team_b.team_memberships.find_by!(user: owner_b))

      expect(described_class.new(admin_user, expense_b).show?).to be(false)
      expect(described_class.new(admin_user, expense_b).approve?).to be(false)
    end
  end
end