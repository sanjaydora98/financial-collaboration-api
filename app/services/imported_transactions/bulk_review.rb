module ImportedTransactions
  class BulkReview
    Result = Struct.new(:outcomes, keyword_init: true)

    def self.call(transactions:, reviewer:, action:, rejection_reason: nil)
      raise ArgumentError, "Action must be accept or reject." unless %w[accept reject].include?(action)
      raise ArgumentError, "Rejection reason is required." if action == "reject" && rejection_reason.blank?

      transactions.each do |transaction|
        policy = ImportedTransactionPolicy.new(reviewer, transaction)
        allowed = action == "accept" ? policy.accept? : policy.reject?
        raise Pundit::NotAuthorizedError unless allowed
      end

      outcomes = transactions.map do |transaction|
        review_one(transaction, reviewer, action, rejection_reason)
      end

      Result.new(outcomes: outcomes)
    end

    def self.review_one(transaction, reviewer, action, rejection_reason)
      if action == "accept"
        expense = Accept.call(imported_transaction: transaction, reviewer: reviewer)
        { id: transaction.id, result: "accepted", expense_id: expense.id }
      else
        Reject.call(imported_transaction: transaction, reviewer: reviewer, reason: rejection_reason)
        { id: transaction.id, result: "rejected" }
      end
    rescue ReviewConflict
      { id: transaction.id, result: "conflict" }
    rescue ActiveRecord::RecordInvalid => error
      { id: transaction.id, result: "validation_error", errors: error.record.errors.to_hash }
    end
    private_class_method :review_one
  end
end