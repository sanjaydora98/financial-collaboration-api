module Expenses
  class Update
    ATTRIBUTES = %i[amount currency merchant description category incurred_on].freeze

    def self.call(expense:, membership:, attributes:, expected_lock_version:)
      Expense.transaction do
        expense.audit_actor_membership_id = membership.id
        expense.lock_version = expected_lock_version
        expense.assign_attributes(attributes.slice(*ATTRIBUTES))
        expense.save!
        expense
      end
    end
  end
end