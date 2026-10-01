module Teams
  class Create
    def self.call(user:, attributes:)
      raise ArgumentError, "user is required" unless user

      Team.transaction do
        team = Team.create!(attributes.merge(creator: user))
        # The user who creates a team becomes its admin immediately, so they can
        # manage members (promote/demote, assign approval stages) right away
        # without a separate bootstrap step. See Teams::PromoteCreatorToAdmin /
        # TeamMembershipPolicy#bootstrap_admin? for the legacy one-time
        # self-promotion path still kept for teams created before this change.
        membership = team.team_memberships.create!(user: user, role: MembershipConstants::ROLES[:admin], active: true)
        [team, membership]
      end
    end
  end
end