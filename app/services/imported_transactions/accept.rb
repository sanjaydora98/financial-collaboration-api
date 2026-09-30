module ImportedTransactions
  class Accept
    def self.call(imported_transaction:, reviewer:)
      expense = nil
      imported_transaction.with_lock do
        membership = active_reviewer_membership(imported_transaction, reviewer)
        raise Pundit::NotAuthorizedError unless ImportedTransactionPolicy.new(reviewer, imported_transaction).accept?
        raise ReviewConflict unless imported_transaction.pending?

        import = Import.find_by!(id: imported_transaction.import_id, team_id: imported_transaction.team_id)
        requester = TeamMembership.find_by!(
          id: import.requested_by_membership_id,
          team_id: imported_transaction.team_id,
          active: true
        )

        expense = Expense.new(
          team_id: imported_transaction.team_id,
          creator_membership: requester,
          member_membership: requester,
          imported_transaction: imported_transaction,
          amount: imported_transaction.amount,
          currency: imported_transaction.currency,
          merchant: imported_transaction.merchant,
          description: imported_transaction.description,
          category: imported_transaction.category,
          incurred_on: imported_transaction.transaction_date,
          status: "draft"
        )
        expense.audit_actor_membership_id = membership.id
        expense.save!

        previous_status = imported_transaction.status
        imported_transaction.update!(
          status: "accepted",
          reviewed_by_membership: membership,
          reviewed_at: Time.current
        )

        AuditLog.create!(
          team_id: imported_transaction.team_id,
          expense: expense,
          actor_membership: membership,
          actor_type: "user",
          category: "workflow",
          event_type: "import_accepted",
          change_data: {
            before: { imported_transaction_status: previous_status },
            after: {
              imported_transaction_status: imported_transaction.status,
              imported_transaction_id: imported_transaction.id,
              expense_id: expense.id,
              reviewer_membership_id: membership.id
            }
          }
        )
      end

      expense
    end

    def self.active_reviewer_membership(imported_transaction, reviewer)
      reviewer.team_memberships.find_by!(team_id: imported_transaction.team_id, active: true)
    end
    private_class_method :active_reviewer_membership
  end
end