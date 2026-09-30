module ImportedTransactions
  class Reject
    def self.call(imported_transaction:, reviewer:, reason:)
      raise ArgumentError, "Rejection reason is required." if reason.blank?

      imported_transaction.with_lock do
        reviewer.team_memberships.find_by!(team_id: imported_transaction.team_id, active: true)
        raise Pundit::NotAuthorizedError unless ImportedTransactionPolicy.new(reviewer, imported_transaction).reject?
        raise ReviewConflict unless imported_transaction.pending?

        imported_transaction.update!(
          status: "rejected",
          reviewed_by_membership: reviewer.team_memberships.find_by!(team_id: imported_transaction.team_id, active: true),
          reviewed_at: Time.current,
          rejection_reason: reason
        )
      end

      imported_transaction
    end
  end
end