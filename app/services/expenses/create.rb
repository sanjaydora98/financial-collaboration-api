module Expenses
  class Create
    ATTRIBUTES = %i[amount currency merchant description category incurred_on].freeze

    def self.call(user:, team:, attributes:)
      Expense.transaction do
        creator_membership = user.team_memberships.find_by!(team_id: team.id, active: true)
        member_id = attributes[:member_membership_id].presence || creator_membership.id
        member_membership = team.team_memberships.find_by!(id: member_id, active: true)

        unless member_membership.id == creator_membership.id || creator_membership.admin?
          raise Pundit::NotAuthorizedError
        end

        expense = team.expenses.build(attributes.slice(*ATTRIBUTES).merge(
          creator_membership: creator_membership,
          member_membership: member_membership,
          status: ExpenseConstants::STATUSES[:draft]
        ))
        expense.audit_actor_membership_id = creator_membership.id
        expense.save!
        expense
      end
    end
  end
end