module Teams
  class PromoteCreatorToAdmin
    def self.call(team:, membership:, user:)
      team.with_lock do
        membership.reload
        unless team.created_by_id == user.id && membership.user_id == user.id &&
            membership.team_id == team.id && membership.active? && membership.creator? &&
            membership.approval_stage.nil?
          raise Pundit::NotAuthorizedError
        end

        membership.update!(role: MembershipConstants::ROLES[:admin])
      end

      membership
    end
  end
end