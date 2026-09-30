module Expenses
  class Delete
    def self.call(expense:, membership:, expected_lock_version:)
      Expense.transaction do
        expense.audit_actor_membership_id = membership.id
        expense.lock_version = expected_lock_version
        expense.update!(deleted_at: Time.current)
        expense
      end
    end
  end
end