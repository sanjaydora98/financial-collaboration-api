class TeamMembershipPolicy < ApplicationPolicy
  def index?
    active_membership.present?
  end

  def create?
    active_membership&.admin?
  end

  def update?
    active_membership&.admin? && record.user_id != user.id
  end

  def destroy?
    active_membership&.admin? && record.user_id != user.id
  end

  def bootstrap_admin?
    user.present? &&
      record.team.created_by_id == user.id &&
      record.user_id == user.id &&
      record.active? && record.creator? &&
      record.approval_stage.nil?
  end

  private

  def active_membership
    return unless user && record&.team_id

    @active_membership ||= user.team_memberships.find_by(team_id: record.team_id, active: true)
  end
end