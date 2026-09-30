module TeamMemberships
  class Create
    def self.call(team:, attributes:)
      team.team_memberships.create!(attributes.merge(team: team))
    end
  end
end