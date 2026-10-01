class ExpensePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return scope.none unless user

      memberships = user.team_memberships.where(active: true)
      all_expense_team_ids = memberships.where(role: MembershipConstants::EXPENSE_VISIBILITY_ROLES).select(:team_id)
      creator_membership_ids = memberships.where(role: MembershipConstants::ROLES[:creator]).select(:id)
      visible = scope.not_deleted.where(team_id: all_expense_team_ids)
        .or(scope.not_deleted.where(creator_membership_id: creator_membership_ids))
        .or(scope.not_deleted.where(member_membership_id: creator_membership_ids))

      visible
    end
  end

  def create?
    membership = active_membership
    return false unless membership && record.draft? && record.creator_membership_id == membership.id
    return true if membership.admin?

    record.member_membership_id == membership.id
  end

  def show?
    return false if record.deleted_at.present?

    membership = active_membership
    return false unless membership

    return true if membership.admin? || membership.approver? || membership.viewer?

    membership.creator? && [record.creator_membership_id, record.member_membership_id].include?(membership.id)
  end

  def update?
    editable_by_membership?
  end

  def destroy?
    editable_by_membership?
  end

  def submit?
    membership = active_membership
    return false unless membership

    membership.admin? || (membership.creator? && record.creator_membership_id == membership.id)
  end

  def initiate_reimbursement?
    membership = active_membership
    return false unless membership

    membership.admin? || (membership.creator? && record.creator_membership_id == membership.id)
  end

  def approve?
    assigned_approval_for_membership?
  end

  def reject?
    assigned_approval_for_membership?
  end

  private

  def active_membership
    return unless user && record

    @active_membership ||= user.team_memberships.find_by(team_id: record.team_id, active: true)
  end

  def editable_by_membership?
    membership = active_membership
    return false unless membership && record.draft? && record.deleted_at.nil?
    return true if membership.admin?

    membership.creator? && record.creator_membership_id == membership.id
  end

  def assigned_approval_for_membership?
    membership = active_membership
    return false unless membership
    return false unless membership.approver? || membership.admin?
    return false unless membership.approval_stage.present?

    record.expense_approvals.exists?(
      approver_membership_id: membership.id,
      stage: membership.approval_stage
    )
  end
end