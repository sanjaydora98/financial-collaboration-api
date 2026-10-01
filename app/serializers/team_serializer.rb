class TeamSerializer
  def self.call(team, membership:)
    {
      id: team.id,
      name: team.name,
      slug: team.slug,
      created_by_id: team.created_by_id,
      membership: membership && TeamMembershipSerializer.call(membership)
    }
  end
end