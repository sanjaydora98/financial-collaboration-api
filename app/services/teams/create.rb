module Teams
  class Create
    def self.call(user:, attributes:)
      raise ArgumentError, "user is required" unless user

      Team.transaction do
        team = Team.create!(attributes.merge(creator: user))
        membership = team.team_memberships.create!(user: user, role: MembershipConstants::ROLES[:creator], active: true)
        [team, membership]
      end
    end
  end
end