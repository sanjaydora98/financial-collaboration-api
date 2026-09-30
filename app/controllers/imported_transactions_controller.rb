class ImportedTransactionsController < ApplicationController
  include BearerAuthentication

  before_action :authenticate_request!
  before_action :set_team
  before_action :set_import, only: %i[index show accept reject]
  before_action :set_imported_transaction, only: %i[show accept reject]

  def index
    authorize @import, :show?
    transactions = policy_scope(@import.imported_transactions).order(transaction_date: :desc, id: :desc)
    render json: { imported_transactions: transactions.map { |transaction| transaction_response(transaction) } }, status: :ok
  end

  def show
    authorize @imported_transaction, :show?
    render json: { imported_transaction: transaction_response(@imported_transaction) }, status: :ok
  end

  def accept
    authorize @imported_transaction, :accept?
    expense = ImportedTransactions::Accept.call(imported_transaction: @imported_transaction, reviewer: current_user)
    render json: {
      imported_transaction: transaction_response(@imported_transaction.reload),
      expense: {
        id: expense.id,
        team_id: expense.team_id,
        creator_membership_id: expense.creator_membership_id,
        member_membership_id: expense.member_membership_id,
        imported_transaction_id: expense.imported_transaction_id,
        amount: expense.amount,
        currency: expense.currency,
        merchant: expense.merchant,
        description: expense.description,
        category: expense.category,
        incurred_on: expense.incurred_on,
        status: expense.status
      }
    }, status: :ok
  rescue ImportedTransactions::ReviewConflict
    render json: { error: { code: "review_conflict", message: "The imported transaction is no longer pending review." } }, status: :conflict
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_imported_transaction", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "review_conflict", message: "An expense has already been created for this imported transaction." } }, status: :conflict
  end

  def reject
    authorize @imported_transaction, :reject?
    reason = params.dig(:imported_transaction, :rejection_reason).to_s
    if reason.blank?
      return render json: { error: { code: "rejection_reason_required", message: "A rejection reason is required." } }, status: :unprocessable_entity
    end

    ImportedTransactions::Reject.call(imported_transaction: @imported_transaction, reviewer: current_user, reason: reason)
    render json: { imported_transaction: transaction_response(@imported_transaction.reload) }, status: :ok
  rescue ImportedTransactions::ReviewConflict
    render json: { error: { code: "review_conflict", message: "The imported transaction is no longer pending review." } }, status: :conflict
  rescue ArgumentError => error
    render json: { error: { code: "invalid_review", message: error.message } }, status: :unprocessable_entity
  end

  def bulk_review
    body_params = request.request_parameters
    ids = body_params["ids"] || params[:ids]
    action = (body_params["action"] || body_params["review_action"] || params[:review_action]).to_s
    rejection_reason = body_params["rejection_reason"] || params[:rejection_reason]
    if !ids.is_a?(Array) || ids.empty? || ids.any?(&:blank?) || ids.uniq.length != ids.length
      return render json: { error: { code: "invalid_ids", message: "Provide a non-empty list of unique imported transaction IDs." } }, status: :unprocessable_entity
    end
    if !%w[accept reject].include?(action)
      return render json: { error: { code: "invalid_action", message: "Action must be accept or reject." } }, status: :unprocessable_entity
    end
    if action == "reject" && rejection_reason.blank?
      return render json: { error: { code: "rejection_reason_required", message: "A rejection reason is required." } }, status: :unprocessable_entity
    end

    transactions_by_id = @team.imported_transactions.where(id: ids).index_by { |transaction| transaction.id.to_s }
    return render json: { error: { code: "not_found", message: "One or more imported transactions were not found." } }, status: :not_found unless transactions_by_id.length == ids.length

    transactions = ids.map { |id| transactions_by_id.fetch(id.to_s) }
    result = ImportedTransactions::BulkReview.call(
      transactions: transactions,
      reviewer: current_user,
      action: action,
      rejection_reason: rejection_reason
    )
    status = if result.outcomes.any? { |outcome| outcome[:result] == "conflict" }
      :conflict
    elsif result.outcomes.any? { |outcome| outcome[:result] == "validation_error" }
      :unprocessable_entity
    else
      :ok
    end
    render json: { results: result.outcomes }, status: status
  rescue ArgumentError => error
    render json: { error: { code: "invalid_bulk_review", message: error.message } }, status: :unprocessable_entity
  end

  private

  def set_team
    @team = policy_scope(Team).find(params[:team_id])
  end

  def set_import
    @import = @team.imports.find(params[:import_id])
  end

  def set_imported_transaction
    @imported_transaction = policy_scope(@import.imported_transactions).find(params[:id])
  end

  def transaction_response(transaction)
    {
      id: transaction.id,
      team_id: transaction.team_id,
      import_id: transaction.import_id,
      provider: transaction.provider,
      external_account_ref: transaction.external_account_ref,
      external_transaction_id: transaction.external_transaction_id,
      amount: transaction.amount,
      currency: transaction.currency,
      merchant: transaction.merchant,
      description: transaction.description,
      category: transaction.category,
      transaction_date: transaction.transaction_date,
      status: transaction.status,
      reviewed_by_membership_id: transaction.reviewed_by_membership_id,
      reviewed_at: transaction.reviewed_at,
      rejection_reason: transaction.rejection_reason
    }
  end
end