module Teams
  class Join
    def self.call(user:, team:)
      raise ArgumentError, "user is required" unless user
      raise ArgumentError, "team is required" unless team

      team.with_lock do
        membership = team.team_memberships.find_by(user_id: user.id)
        raise ActiveRecord::RecordNotUnique if membership && membership.active?

        team.team_memberships.create!(user: user, role: MembershipConstants::ROLES[:viewer], active: true)
      end
    end
  end
end
