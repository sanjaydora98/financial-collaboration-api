class ImportedTransactionPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return scope.none unless user

      team_ids = user.team_memberships.where(active: true).select(:team_id)
      scope.where(team_id: team_ids)
    end
  end

  def show?
    active_membership.present?
  end

  def accept?
    reviewer?
  end

  def reject?
    reviewer?
  end

  private

  def reviewer?
    membership = active_membership
    membership.present? && (membership.admin? || membership.approver?)
  end

  def active_membership
    return unless user && record

    @active_membership ||= user.team_memberships.find_by(team_id: record.team_id, active: true)
  end
end