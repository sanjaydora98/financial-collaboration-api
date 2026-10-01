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
    it "creates a team and makes its creator an active admin membership transactionally" do
      current_user = user("creator@example.com")

      expect {
        post "/teams", params: { team: { name: "Design Team", slug: "design-team" } }, headers: headers_for(current_user), as: :json
      }.to change(Team, :count).by(1).and change(TeamMembership, :count).by(1)

      team = Team.find_by!(slug: "design-team")
      membership = TeamMembership.find_by!(team: team, user: current_user)
      expect(response).to have_http_status(:created)
      expect(team.created_by_id).to eq(current_user.id)
      expect(membership).to have_attributes(role: "admin", active: true, approval_stage: nil)
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

  describe "creator bootstrap (legacy data path)" do
    # New teams now grant their creator the "admin" role directly (see
    # "team creation and listing" above), so this endpoint is no longer
    # exercised by the normal create flow. It is kept, unchanged, so any
    # pre-existing "creator" role membership row (created before this fix)
    # can still be self-promoted to admin without a data migration.
    def legacy_creator_team(creator, slug:)
      team = Team.create!(name: "Legacy #{slug}", slug: slug, creator: creator)
      membership = team.team_memberships.create!(user: creator, role: "creator", active: true)
      [team, membership]
    end

    it "promotes the creator's existing legacy membership without creating another membership" do
      creator = user("bootstrap@example.com")
      team, membership = legacy_creator_team(creator, slug: "bootstrap-team")

      expect { bootstrap_admin(team, creator) }.not_to change(TeamMembership, :count)

      expect(response).to have_http_status(:ok)
      expect(membership.reload).to have_attributes(role: "admin", active: true, approval_stage: nil)
      expect(team.team_memberships.count).to eq(1)
    end

    it "cannot promote another user's membership through the bootstrap endpoint" do
      creator = user("bootstrap-owner@example.com")
      team, = legacy_creator_team(creator, slug: "bootstrap-target-team")
      other_user = user("bootstrap-other@example.com")

      post "/teams/#{team.id}/bootstrap_admin", params: { user_id: other_user.id }, headers: headers_for(creator), as: :json

      expect(response).to have_http_status(:ok)
      expect(team.team_memberships.find_by!(user: creator).role).to eq("admin")
      expect(team.team_memberships.exists?(user: other_user)).to be(false)
    end

    it "does not allow an unrelated team member to use creator bootstrap" do
      creator = user("actual-creator@example.com")
      team, = legacy_creator_team(creator, slug: "bootstrap-forbidden-team")
      other_user = user("other-creator@example.com")
      membership = TeamMembership.create!(team: team, user: other_user, role: "viewer")

      post "/teams/#{team.id}/bootstrap_admin", headers: headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(membership.reload.role).to eq("viewer")
    end

    it "is unavailable for newly created teams because the creator is already admin" do
      creator = user("already-admin@example.com")
      team = create_team(creator, slug: "already-admin-team")

      post "/teams/#{team.id}/bootstrap_admin", headers: headers_for(creator), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(team.team_memberships.find_by!(user: creator).role).to eq("admin")
    end
  end

  describe "team joining" do
    it "allows an authenticated user to join a team by its join code" do
      creator = user("join-team-creator@example.com")
      team = create_team(creator, slug: "join-code-team")
      joiner = user("joiner@example.com")

      expect {
        post "/teams/join",
          params: { team: { join_code: team.slug } },
          headers: headers_for(joiner), as: :json
      }.to change(TeamMembership, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(team.team_memberships.find_by!(user: joiner)).to have_attributes(role: "viewer", active: true)
      expect(JSON.parse(response.body).dig("team", "slug")).to eq(team.slug)
    end

    it "rejects duplicate joins and invalid join codes" do
      creator = user("join-team-creator-2@example.com")
      team = create_team(creator, slug: "join-code-team-2")
      member = user("existing-join-member@example.com")
      TeamMembership.create!(team: team, user: member, role: "viewer")

      post "/teams/join", params: { team: { join_code: team.slug } }, headers: headers_for(member), as: :json
      expect(response).to have_http_status(:conflict)

      post "/teams/join", params: { team: { join_code: "missing-team" } }, headers: headers_for(member), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns the translated not_found error body for an unknown join code (regression for missing I18n key)" do
      requester = user("join-team-unknown-code@example.com")

      post "/teams/join", params: { team: { join_code: "no-such-team-code" } }, headers: headers_for(requester), as: :json

      expect(response).to have_http_status(:not_found)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq("team_not_found")
      expect(body.dig("error", "message")).to eq("Team not found.")
      expect(body.dig("error", "message")).not_to include("Translation missing")
    end
    it "ignores any client-supplied role or approval_stage and always joins as viewer" do
      creator = user("join-team-creator-3@example.com")
      team = create_team(creator, slug: "join-code-team-3")
      joiner = user("joiner-role-spoof@example.com")

      post "/teams/join",
        params: { team: { join_code: team.slug, role: "admin", approval_stage: "finance" } },
        headers: headers_for(joiner), as: :json

      expect(response).to have_http_status(:created)
      expect(team.team_memberships.find_by!(user: joiner)).to have_attributes(role: "viewer", active: true, approval_stage: nil)
    end
  end

  describe "membership management" do
    it "allows an admin to add, update, and deactivate members" do
      admin = user("membership-admin@example.com")
      team = create_team(admin, slug: "membership-team")
      new_user = user("new-member@example.com")

      post "/teams/#{team.id}/memberships",
        params: { membership: { user_id: new_user.id, role: "viewer" } },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:created)
      created_membership = JSON.parse(response.body).fetch("membership")
      membership_id = created_membership.fetch("id")
      membership_public_id = created_membership.fetch("public_id")

      expect(created_membership.dig("user", "name")).to eq(new_user.name)
      expect(created_membership.dig("user", "email")).to eq(new_user.email)
      expect(created_membership.dig("user").keys).to contain_exactly("name", "email")
      expect(membership_public_id).to match(/\A[0-9a-f-]{36}\z/i)
      expect(membership_public_id).not_to eq(membership_id.to_s)

      get "/teams/#{team.id}/memberships", headers: headers_for(admin)
      listed_membership = JSON.parse(response.body).fetch("memberships").find { |item| item["public_id"] == membership_public_id }
      expect(listed_membership.dig("user", "name")).to eq(new_user.name)
      expect(listed_membership.dig("user", "email")).to eq(new_user.email)

      patch "/teams/#{team.id}/memberships/#{membership_public_id}",
        params: { membership: { role: "approver", approval_stage: "manager" } },
        headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(team.team_memberships.find(membership_id)).to have_attributes(role: "approver", approval_stage: "manager")

      delete "/teams/#{team.id}/memberships/#{membership_public_id}", headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(team.team_memberships.find(membership_id).active).to be(false)
    end

    it "rejects duplicate memberships with 409 and does not create another row" do
      admin = user("duplicate-admin@example.com")
      team = create_team(admin, slug: "duplicate-membership-team")
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

    it "allows active members to view memberships but denies non-admin membership administration" do
      owner = user("member-read-owner@example.com")
      team = create_team(owner, slug: "member-read-team")
      member = user("member-reader@example.com")
      TeamMembership.create!(team: team, user: member, role: "creator")
      another_user = user("member-to-add@example.com")

      get "/teams/#{team.id}/memberships", headers: headers_for(member)
      expect(response).to have_http_status(:ok)

      post "/teams/#{team.id}/memberships",
        params: { membership: { user_id: another_user.id, role: "viewer" } },
        headers: headers_for(member), as: :json

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
      membership = team.team_memberships.find_by!(user: admin)

      patch "/teams/#{team.id}/memberships/#{membership.id}",
        params: { membership: { role: "viewer" } }, headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:forbidden)

      delete "/teams/#{team.id}/memberships/#{membership.id}", headers: headers_for(admin)
      expect(response).to have_http_status(:forbidden)
      expect(membership.reload).to have_attributes(role: "admin", active: true)
    end

    it "rejects invalid role and approval-stage combinations during updates" do
      admin = user("invalid-membership-admin@example.com")
      team = create_team(admin, slug: "invalid-membership-update-team")
      target = TeamMembership.create!(team: team, user: user("invalid-membership-target@example.com"), role: "viewer")

      patch "/teams/#{team.id}/memberships/#{target.public_id}",
        params: { membership: { role: "approver", approval_stage: nil } },
        headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      patch "/teams/#{team.id}/memberships/#{target.public_id}",
        params: { membership: { role: "viewer", approval_stage: "finance" } },
        headers: headers_for(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(target.reload).to have_attributes(role: "viewer", approval_stage: nil)
    end

    it "denies non-admin membership updates" do
      owner = user("nonadmin-update-owner@example.com")
      team = create_team(owner, slug: "nonadmin-update-team")
      viewer = user("nonadmin-updater@example.com")
      TeamMembership.create!(team: team, user: viewer, role: "viewer")
      target = TeamMembership.create!(team: team, user: user("nonadmin-update-target@example.com"), role: "viewer")

      patch "/teams/#{team.id}/memberships/#{target.public_id}",
        params: { membership: { role: "approver", approval_stage: "manager" } },
        headers: headers_for(viewer), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(target.reload.role).to eq("viewer")
    end

    it "allows an admin to reactivate an inactive member by public identifier" do
      admin = user("reactivate-admin@example.com")
      team = create_team(admin, slug: "reactivate-member-team")
      target = TeamMembership.create!(team: team, user: user("reactivate-target@example.com"), role: "viewer", active: false)

      patch "/teams/#{team.id}/memberships/#{target.public_id}",
        params: { membership: { active: true } }, headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("membership", "status")).to eq("active")
      expect(target.reload.active).to be(true)
    end

    it "returns 404 for cross-team membership references and ignores a forged team_id" do
      admin_a = user("team-a-admin@example.com")
      team_a = create_team(admin_a, slug: "team-a-membership")
      user_b = user("team-b-owner@example.com")
      team_b = create_team(user_b, slug: "team-b-membership")
      membership_b = team_b.team_memberships.find_by!(user: user_b)

      patch "/teams/#{team_a.id}/memberships/#{membership_b.public_id}",
        params: { membership: { role: "admin", team_id: team_a.id } },
        headers: headers_for(admin_a), as: :json

      expect(response).to have_http_status(:not_found)
      expect(membership_b.reload).to have_attributes(team_id: team_b.id, role: "admin")
    end

    it "prevents an admin in Team A from viewing or modifying Team B" do
      admin_a = user("cross-admin@example.com")
      team_a = create_team(admin_a, slug: "cross-a")
      owner_b = user("cross-owner@example.com")
      team_b = create_team(owner_b, slug: "cross-b")
      membership_b = team_b.team_memberships.find_by!(user: owner_b)

      get "/teams/#{team_b.id}/memberships", headers: headers_for(admin_a)
      expect(response).to have_http_status(:not_found)

      patch "/teams/#{team_b.id}/memberships/#{membership_b.id}",
        params: { membership: { role: "admin" } }, headers: headers_for(admin_a), as: :json
      expect(response).to have_http_status(:not_found)
      expect(membership_b.reload.role).to eq("admin")
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