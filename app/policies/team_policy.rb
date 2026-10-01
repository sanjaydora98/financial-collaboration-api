class TeamPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.joins(:team_memberships)
        .where(team_memberships: { user_id: user.id, active: true })
        .distinct
    end
  end

  def create?
    user.present?
  end

  def join?
    user.present?
  end

  def show?
    active_membership.present?
  end

  def manage_members?
    active_membership&.admin?
  end

  private

  def active_membership
    return unless user && record

    @active_membership ||= user.team_memberships.find_by(team_id: record.id, active: true)
  end
end