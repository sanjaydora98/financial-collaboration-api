class ImportPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return scope.none unless user

      team_ids = user.team_memberships.where(active: true).select(:team_id)
      scope.where(team_id: team_ids)
    end
  end

  def index?
    active_membership.present?
  end

  def show?
    active_membership.present?
  end

  def create?
    membership = active_membership
    membership.present? && !membership.viewer?
  end

  private

  def active_membership
    return unless user && record&.team_id

    @active_membership ||= user.team_memberships.find_by(team_id: record.team_id, active: true)
  end
end