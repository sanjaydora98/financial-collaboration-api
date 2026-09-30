require "rails_helper"

RSpec.describe "Teams API", type: :request do
  def user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  def headers_for(user)
    token = Authentication::SessionIssuer.call(user: user).token
    { "Authorization" => "Bearer #{token}" }
  end

  def create_team(user, slug: SecureRandom.hex(5))
    Teams::Create.call(user: user, attributes: { name: "Team #{slug}", slug: slug }).first
  end

  def bootstrap_admin(team, user)
    post "/teams/#{team.id}/bootstrap_admin", headers: headers_for(user), as: :json
  end

  describe "team creation and listing" do
    it "creates a team and exactly one active creator membership transactionally" do
      current_user = user("creator@example.com")

      expect {
        post "/teams", params: { team: { name: "Design Team", slug: "design-team" } }, headers: headers_for(current_user), as: :json
      }.to change(Team, :count).by(1).and change(TeamMembership, :count).by(1)

      team = Team.find_by!(slug: "design-team")
      membership = TeamMembership.find_by!(team: team, user: current_user)
      expect(response).to have_http_status(:created)
      expect(team.created_by_id).to eq(current_user.id)
      expect(membership).to have_attributes(role: "creator", active: true, approval_stage: nil)
      expect(team.team_memberships.count).to eq(1)
    end

    it "requires authentication to create a team" do
      post "/teams", params: { team: { name: "Private", slug: "private" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Team.count).to eq(0)
    end

    it "lists only teams with an active membership for the current user" do
      current_user = user("team-list@example.com")
      own_team = create_team(current_user, slug: "own-team")
      other_user = user("other-team@example.com")
      create_team(other_user, slug: "other-team")

      get "/teams", headers: headers_for(current_user)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("teams").map { |item| item.fetch("id") }).to eq([own_team.id])
    end

    it "returns 404 for a team the authenticated user does not belong to" do
      outsider = user("outsider@example.com")
      team = create_team(user("owner@example.com"), slug: "private-team")

      get "/teams/#{team.id}", headers: headers_for(outsider)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "creator bootstrap" do
    it "promotes the creator's existing membership without creating another membership" do
      creator = user("bootstrap@example.com")
      team = create_team(creator, slug: "bootstrap-team")
      membership = team.team_memberships.find_by!(user: creator)

      expect { bootstrap_admin(team, creator) }.not_to change(TeamMembership, :count)

      expect(response).to have_http_status(:ok)
      expect(membership.reload).to have_attributes(role: "admin", active: true, approval_stage: nil)
      expect(team.team_memberships.count).to eq(1)
    end

    it "cannot promote another user's membership through the bootstrap endpoint" do
      creator = user("bootstrap-owner@example.com")
      team = create_team(creator, slug: "bootstrap-target-team")
      other_user = user("bootstrap-other@example.com")

      post "/teams/#{team.id}/bootstrap_admin", params: { user_id: other_user.id }, headers: headers_for(creator), as: :json

      expect(response).to have_http_status(:ok)
      expect(team.team_memberships.find_by!(user: creator).role).to eq("admin")
      expect(team.team_memberships.exists?(user: other_user)).to be(false)
    end

    it "does not allow an unrelated team member to use creator bootstrap" do
      creator = user("actual-creator@example.com")
      team = create_team(creator, slug: "bootstrap-forbidden-team")
      other_user = user("other-creator@example.com")
      membership = TeamMembership.create!(team: team, user: other_user, role: "viewer")

      post "/teams/#{team.id}/bootstrap_admin", headers: headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(membership.reload.role).to eq("viewer")
    end
  end

  describe "membership management" do
    it "allows an admin to add, update, and deactivate members" do
      admin = user("membership-admin@example.com")
      team = create_team(admin, slug: "membership-team")
      bootstrap_admin(team, admin)
      new_user = user("new-member@example.com")

      post "/teams/#{team.id}/memberships",
        params: { membership: { user_id: new_user.id, role: "viewer" } },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:created)
      membership_id = JSON.parse(response.body).dig("membership", "id")

      patch "/teams/#{team.id}/memberships/#{membership_id}",
        params: { membership: { role: "approver", approval_stage: "manager" } },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(team.team_memberships.find(membership_id)).to have_attributes(role: "approver", approval_stage: "manager")

      delete "/teams/#{team.id}/memberships/#{membership_id}", headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(team.team_memberships.find(membership_id).active).to be(false)
    end

    it "rejects duplicate memberships with 409 and does not create another row" do
      admin = user("duplicate-admin@example.com")
      team = create_team(admin, slug: "duplicate-membership-team")
      bootstrap_admin(team, admin)
      member = user("existing-member@example.com")
      TeamMembership.create!(team: team, user: member, role: "viewer")

      expect {
        post "/teams/#{team.id}/memberships",
          params: { membership: { user_id: member.id, role: "viewer" } },
          headers: headers_for(admin), as: :json
      }.not_to change(TeamMembership, :count)
      expect(response).to have_http_status(:conflict)
    end

    it "enforces one active Manager and one active Finance approval slot" do
      admin = user("stage-slots-admin@example.com")
      team = create_team(admin, slug: "stage-slots-team")
      bootstrap_admin(team, admin)
      manager_user = user("manager-slot@example.com")
      finance_user = user("finance-slot@example.com")

      post "/teams/#{team.id}/memberships",
        params: { membership: { user_id: manager_user.id, role: "approver", approval_stage: "manager" } },
        headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:created)

      post "/teams/#{team.id}/memberships",
        params: { membership: { user_id: finance_user.id, role: "admin", approval_stage: "manager" } },
        headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:conflict)

      post "/teams/#{team.id}/memberships",
        params: { membership: { user_id: finance_user.id, role: "admin", approval_stage: "finance" } },
        headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:created)

      other_finance_user = user("other-finance-slot@example.com")
      post "/teams/#{team.id}/memberships",
        params: { membership: { user_id: other_finance_user.id, role: "approver", approval_stage: "finance" } },
        headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:conflict)
    end

    it "allows active members to view memberships but denies creator membership administration" do
      creator = user("member-reader@example.com")
      team = create_team(creator, slug: "member-read-team")
      another_user = user("member-to-add@example.com")

      get "/teams/#{team.id}/memberships", headers: headers_for(creator)
      expect(response).to have_http_status(:ok)

      post "/teams/#{team.id}/memberships",
        params: { membership: { user_id: another_user.id, role: "viewer" } },
        headers: headers_for(creator), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "denies viewers administrative membership operations" do
      owner = user("viewer-team-owner@example.com")
      team = create_team(owner, slug: "viewer-team")
      viewer = user("viewer@example.com")
      TeamMembership.create!(team: team, user: viewer, role: "viewer")

      post "/teams/#{team.id}/memberships",
        params: { membership: { user_id: user("target@example.com").id, role: "viewer" } },
        headers: headers_for(viewer), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "does not permit self-demotion or self-deactivation for an admin" do
      admin = user("no-self-demotion@example.com")
      team = create_team(admin, slug: "no-self-demotion-team")
      bootstrap_admin(team, admin)
      membership = team.team_memberships.find_by!(user: admin)

      patch "/teams/#{team.id}/memberships/#{membership.id}",
        params: { membership: { role: "viewer" } }, headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:forbidden)

      delete "/teams/#{team.id}/memberships/#{membership.id}", headers: headers_for(admin)
      expect(response).to have_http_status(:forbidden)
      expect(membership.reload).to have_attributes(role: "admin", active: true)
    end

    it "returns 404 for cross-team membership references and ignores a forged team_id" do
      admin_a = user("team-a-admin@example.com")
      team_a = create_team(admin_a, slug: "team-a-membership")
      bootstrap_admin(team_a, admin_a)
      user_b = user("team-b-owner@example.com")
      team_b = create_team(user_b, slug: "team-b-membership")
      membership_b = team_b.team_memberships.find_by!(user: user_b)

      patch "/teams/#{team_a.id}/memberships/#{membership_b.id}",
        params: { membership: { role: "admin", team_id: team_a.id } },
        headers: headers_for(admin_a), as: :json

      expect(response).to have_http_status(:not_found)
      expect(membership_b.reload).to have_attributes(team_id: team_b.id, role: "creator")
    end

    it "prevents an admin in Team A from viewing or modifying Team B" do
      admin_a = user("cross-admin@example.com")
      team_a = create_team(admin_a, slug: "cross-a")
      bootstrap_admin(team_a, admin_a)
      owner_b = user("cross-owner@example.com")
      team_b = create_team(owner_b, slug: "cross-b")
      membership_b = team_b.team_memberships.find_by!(user: owner_b)

      get "/teams/#{team_b.id}/memberships", headers: headers_for(admin_a)
      expect(response).to have_http_status(:not_found)

      patch "/teams/#{team_b.id}/memberships/#{membership_b.id}",
        params: { membership: { role: "admin" } }, headers: headers_for(admin_a), as: :json
      expect(response).to have_http_status(:not_found)
      expect(membership_b.reload.role).to eq("creator")
    end

    it "does not authorize inactive or non-member users to access a team" do
      owner = user("inactive-owner@example.com")
      team = create_team(owner, slug: "inactive-team")
      inactive_user = user("inactive-member@example.com")
      TeamMembership.create!(team: team, user: inactive_user, role: "viewer", active: false)
      no_membership_user = user("no-membership@example.com")

      get "/teams/#{team.id}", headers: headers_for(inactive_user)
      expect(response).to have_http_status(:not_found)

      get "/teams/#{team.id}/memberships", headers: headers_for(no_membership_user)
      expect(response).to have_http_status(:not_found)
    end
  end
end