require "rails_helper"

RSpec.describe "Team services" do
  def create_user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  it "creates a team and makes its creator an active admin membership in one service operation" do
    user = create_user("team-service@example.com")

    expect {
      @team, @membership = Teams::Create.call(user: user, attributes: { name: "Service Team", slug: "service-team" })
    }.to change(Team, :count).by(1).and change(TeamMembership, :count).by(1)

    expect(@team.creator).to eq(user)
    expect(@membership).to have_attributes(user: user, role: "admin", active: true, approval_stage: nil)
    expect(@team.team_memberships.count).to eq(1)
  end

  it "promotes a legacy creator-role membership transactionally without inserting another membership" do
    # Simulates a membership row created before team creators were granted
    # admin directly (see "creates a team..." above); Teams::PromoteCreatorToAdmin
    # remains available to upgrade any pre-existing "creator" role membership.
    user = create_user("promotion-service@example.com")
    team = Team.create!(name: "Promotion Team", slug: "promotion-team", creator: user)
    membership = team.team_memberships.create!(user: user, role: "creator", active: true)

    expect {
      Teams::PromoteCreatorToAdmin.call(team: team, membership: membership, user: user)
    }.not_to change(TeamMembership, :count)
    expect(membership.reload).to have_attributes(role: "admin", active: true, approval_stage: nil)
  end

  it "rejects bootstrap promotion for a non-creator membership" do
    creator = create_user("promotion-owner@example.com")
    team, = Teams::Create.call(user: creator, attributes: { name: "Protected Team", slug: "protected-team" })
    other_user = create_user("promotion-other@example.com")
    membership = TeamMembership.create!(team: team, user: other_user, role: "viewer")

    expect {
      Teams::PromoteCreatorToAdmin.call(team: team, membership: membership, user: other_user)
    }.to raise_error(Pundit::NotAuthorizedError)
    expect(membership.reload.role).to eq("viewer")
  end

  it "protects the last active admin at the membership update service boundary" do
    user = create_user("last-active-admin@example.com")
    team, membership = Teams::Create.call(user: user, attributes: { name: "Last Admin Team", slug: "last-admin-team" })

    expect {
      TeamMemberships::Update.call(team: team, membership: membership, attributes: { active: false })
    }.to raise_error(TeamMemberships::Update::LastActiveAdminError)
    expect {
      TeamMemberships::Update.call(team: team, membership: membership, attributes: { role: "viewer" })
    }.to raise_error(TeamMemberships::Update::LastActiveAdminError)
    expect(membership.reload).to have_attributes(role: "admin", active: true)
  end
end