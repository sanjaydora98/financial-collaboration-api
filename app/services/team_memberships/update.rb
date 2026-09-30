module TeamMemberships
  class Update
    class LastActiveAdminError < StandardError; end

    def self.call(team:, membership:, attributes:)
      team.with_lock do
        membership.reload
        next_role = attributes.fetch(:role, membership.role)
        next_active = attributes.fetch(:active, membership.active?)

        if membership.active? && membership.admin? && (!next_active || next_role != "admin")
          other_active_admin_exists = team.team_memberships.where(active: true).admin.where.not(id: membership.id).exists?
          raise LastActiveAdminError unless other_active_admin_exists
        end

        membership.update!(attributes)
      end

      membership
    end
  end
end