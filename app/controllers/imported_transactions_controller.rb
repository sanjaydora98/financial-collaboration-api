class ImportedTransactionsController < ApplicationController
  include BearerAuthentication

  before_action :authenticate_request!
  before_action :set_team
  before_action :set_import, only: %i[index show accept reject]
  before_action :set_imported_transaction, only: %i[show accept reject]

  def index
    authorize @import, :show?
    transactions = policy_scope(@import.imported_transactions).order(transaction_date: :desc, id: :desc)
    render json: { imported_transactions: transactions.map { |transaction| ImportedTransactionSerializer.call(transaction) } }, status: :ok
  end

  def show
    authorize @imported_transaction, :show?
    render json: { imported_transaction: ImportedTransactionSerializer.call(@imported_transaction) }, status: :ok
  end

  def accept
    authorize @imported_transaction, :accept?
    expense = ImportedTransactions::Accept.call(imported_transaction: @imported_transaction, reviewer: current_user)
    render json: {
      imported_transaction: ImportedTransactionSerializer.call(@imported_transaction.reload),
      expense: ExpenseSerializer.call(expense, imported_transaction: true)
    }, status: :ok
  rescue ImportedTransactions::ReviewConflict
    render json: { error: { code: "review_conflict", message: I18n.t("errors.import.review_not_pending") } }, status: :conflict
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_imported_transaction", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "review_conflict", message: I18n.t("errors.import.expense_exists") } }, status: :conflict
  end

  def reject
    authorize @imported_transaction, :reject?
    reason = params.dig(:imported_transaction, :rejection_reason).to_s
    if reason.blank?
      return render json: { error: { code: "rejection_reason_required", message: I18n.t("errors.import.rejection_reason_required") } }, status: :unprocessable_entity
    end

    ImportedTransactions::Reject.call(imported_transaction: @imported_transaction, reviewer: current_user, reason: reason)
    render json: { imported_transaction: ImportedTransactionSerializer.call(@imported_transaction.reload) }, status: :ok
  rescue ImportedTransactions::ReviewConflict
    render json: { error: { code: "review_conflict", message: I18n.t("errors.import.review_not_pending") } }, status: :conflict
  rescue ArgumentError => error
    render json: { error: { code: "invalid_review", message: error.message } }, status: :unprocessable_entity
  end

  def bulk_review
    body_params = request.request_parameters
    ids = body_params["ids"] || params[:ids]
    action = (body_params["action"] || body_params["review_action"] || params[:review_action]).to_s
    rejection_reason = body_params["rejection_reason"] || params[:rejection_reason]

    normalized_ids = Array(ids).map do |id|
      Integer(id.to_s, 10)
    rescue ArgumentError
      nil
    end

    if !ids.is_a?(Array) || ids.empty? || normalized_ids.any?(nil) || normalized_ids.uniq.length != normalized_ids.length || normalized_ids.length > ImportConstants::BULK_REVIEW_MAX_IDS
      return render json: { error: { code: "invalid_ids", message: I18n.t("errors.import.invalid_ids", max: ImportConstants::BULK_REVIEW_MAX_IDS) } }, status: :unprocessable_entity
    end
    if !ImportConstants::REVIEW_ACTIONS.include?(action)
      return render json: { error: { code: "invalid_action", message: I18n.t("errors.import.invalid_action") } }, status: :unprocessable_entity
    end
    if action == "reject" && rejection_reason.blank?
      return render json: { error: { code: "rejection_reason_required", message: I18n.t("errors.import.rejection_reason_required") } }, status: :unprocessable_entity
    end

    transactions_by_id = @team.imported_transactions.where(id: normalized_ids).index_by { |transaction| transaction.id.to_s }
    return render json: { error: { code: "not_found", message: I18n.t("errors.import.transactions_not_found") } }, status: :not_found unless transactions_by_id.length == normalized_ids.length

    transactions = normalized_ids.map { |id| transactions_by_id.fetch(id.to_s) }
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

end