class ExpensesController < ApplicationController
  include BearerAuthentication

  before_action :authenticate_request!
  before_action :set_team
  before_action :set_expense, only: %i[show update destroy]
  before_action :set_workflow_expense, only: %i[submit approval create_reimbursement]

  def index
    authorize @team, :show?
    expenses = policy_scope(@team.expenses).order(created_at: :desc, id: :desc)
    render json: { expenses: expenses.map { |expense| expense_response(expense) } }, status: :ok
  end

  def create
    creator_membership = current_membership
    target_id = expense_params[:member_membership_id].presence || creator_membership.id
    target_membership = @team.team_memberships.find_by!(id: target_id, active: true)
    candidate = @team.expenses.build(
      creator_membership: creator_membership,
      member_membership: target_membership,
      status: ExpenseConstants::STATUSES[:draft]
    )
    authorize candidate, :create?

    expense = Expenses::Create.call(
      user: current_user,
      team: @team,
      attributes: expense_params
    )
    render json: { expense: expense_response(expense) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_expense", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "expense_conflict", message: I18n.t("errors.expense.conflict") } }, status: :conflict
  end

  def show
    authorize @expense, :show?
    render json: { expense: expense_response(@expense) }, status: :ok
  end

  def update
    authorize @expense, :update?
    version = expected_lock_version
    return missing_lock_version unless version

    expense = Expenses::Update.call(
      expense: @expense,
      membership: current_membership,
      attributes: expense_params,
      expected_lock_version: version
    )
    render json: { expense: expense_response(expense) }, status: :ok
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_expense", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::StaleObjectError
    render_stale_conflict
  end

  def destroy
    authorize @expense, :destroy?
    version = expected_lock_version
    return missing_lock_version unless version

    expense = Expenses::Delete.call(
      expense: @expense,
      membership: current_membership,
      expected_lock_version: version
    )
    render json: { expense: expense_response(expense) }, status: :ok
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_expense", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::StaleObjectError
    render_stale_conflict
  end

  def submit
    authorize @expense, :submit?
    expense = Expenses::Submit.call(expense: @expense, user: current_user)
    render json: {
      expense: expense_response(expense),
      approvals: expense.expense_approvals.order(:step).map { |approval| ExpenseApprovalSerializer.call(approval) }
    }, status: :ok
  rescue Expenses::WorkflowConflict => error
    render_workflow_conflict(error)
  rescue Expenses::WorkflowConfigurationError => error
    render json: { error: { code: "approval_configuration", message: error.message } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_submission", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "submission_conflict", message: I18n.t("errors.approval.steps_exist") } }, status: :conflict
  end

  def approval
    decision_params = params.fetch(:approval, ActionController::Parameters.new).permit(:decision, :rejection_reason)
    decision = decision_params[:decision].to_s
    rejection_reason = decision_params[:rejection_reason]
    unless Expenses::Review::DECISIONS.include?(decision)
      return render json: { error: { code: "invalid_decision", message: I18n.t("errors.approval.invalid_decision") } }, status: :unprocessable_entity
    end
    if decision == ApprovalConstants::DECISIONS[:reject] && rejection_reason.blank?
      return render json: { error: { code: "rejection_reason_required", message: I18n.t("errors.approval.rejection_reason_required") } }, status: :unprocessable_entity
    end

    authorize @expense, :approve?
    expense = Expenses::Review.call(
      expense: @expense,
      user: current_user,
      decision: decision,
      rejection_reason: rejection_reason
    )
    approval = expense.expense_approvals.find_by!(approver_membership_id: current_membership.id, stage: current_membership.approval_stage)
    render json: { expense: expense_response(expense), approval: ExpenseApprovalSerializer.call(approval) }, status: :ok
  rescue Expenses::WorkflowConflict => error
    render_workflow_conflict(error)
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_approval", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "approval_conflict", message: I18n.t("errors.approval.conflict") } }, status: :conflict
  end

  def create_reimbursement
    authorize @expense, :initiate_reimbursement?
    reimbursement = Reimbursements::Create.call(expense: @expense, user: current_user)
    render json: {
      expense: expense_response(@expense.reload),
      reimbursement: ReimbursementSerializer.call(reimbursement)
    }, status: :created
  rescue Reimbursements::Conflict
    render json: { error: { code: "reimbursement_conflict", message: I18n.t("errors.reimbursement.ineligible") } }, status: :conflict
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_reimbursement", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "reimbursement_conflict", message: I18n.t("errors.reimbursement.exists") } }, status: :conflict
  end

  private

  def set_team
    @team = policy_scope(Team).find(params[:team_id])
  end

  def set_expense
    @expense = @team.expenses.not_deleted.find(params[:id])
  end

  def set_workflow_expense
    @expense = @team.expenses.find(params[:id] || params[:expense_id])
  end

  def current_membership
    @current_membership ||= current_user.team_memberships.find_by!(team_id: @team.id, active: true)
  end

  def expense_params
    params.fetch(:expense, ActionController::Parameters.new)
      .permit(:member_membership_id, :amount, :currency, :merchant, :description, :category, :incurred_on)
      .to_h.symbolize_keys
  end

  def expected_lock_version
    value = params[:lock_version] || params.dig(:expense, :lock_version)
    Integer(value.to_s, 10) if value.present?
  rescue ArgumentError
    nil
  end

  def missing_lock_version
    render json: { error: { code: "lock_version_required", message: I18n.t("errors.expense.lock_version_required") } }, status: :unprocessable_entity
  end

  def render_stale_conflict
    @expense.reload
    render json: {
      error: {
        code: "stale_expense",
        message: I18n.t("errors.expense.stale"),
        current_lock_version: @expense.lock_version
      }
    }, status: :conflict
  end

  def render_workflow_conflict(error)
    render json: { error: { code: "workflow_conflict", message: error.message.presence || I18n.t("errors.approval.workflow_conflict") } }, status: :conflict
  end

  def expense_response(expense)
    ExpenseSerializer.call(expense)
  end
end