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
      status: "draft"
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
    render json: { error: { code: "expense_conflict", message: "The expense conflicts with an existing record." } }, status: :conflict
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
      approvals: expense.expense_approvals.order(:step).map { |approval| approval_response(approval) }
    }, status: :ok
  rescue Expenses::WorkflowConflict => error
    render_workflow_conflict(error)
  rescue Expenses::WorkflowConfigurationError => error
    render json: { error: { code: "approval_configuration", message: error.message } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_submission", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "submission_conflict", message: "The expense already has approval steps." } }, status: :conflict
  end

  def approval
    decision_params = params.fetch(:approval, ActionController::Parameters.new).permit(:decision, :rejection_reason)
    decision = decision_params[:decision].to_s
    rejection_reason = decision_params[:rejection_reason]
    unless Expenses::Review::DECISIONS.include?(decision)
      return render json: { error: { code: "invalid_decision", message: "Decision must be approve or reject." } }, status: :unprocessable_entity
    end
    if decision == "reject" && rejection_reason.blank?
      return render json: { error: { code: "rejection_reason_required", message: "A rejection reason is required." } }, status: :unprocessable_entity
    end

    authorize @expense, :approve?
    expense = Expenses::Review.call(
      expense: @expense,
      user: current_user,
      decision: decision,
      rejection_reason: rejection_reason
    )
    approval = expense.expense_approvals.find_by!(approver_membership_id: current_membership.id, stage: current_membership.approval_stage)
    render json: { expense: expense_response(expense), approval: approval_response(approval) }, status: :ok
  rescue Expenses::WorkflowConflict => error
    render_workflow_conflict(error)
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_approval", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "approval_conflict", message: "The approval decision conflicts with an existing decision." } }, status: :conflict
  end

  def create_reimbursement
    authorize @expense, :initiate_reimbursement?
    reimbursement = Reimbursements::Create.call(expense: @expense, user: current_user)
    render json: {
      expense: expense_response(@expense.reload),
      reimbursement: reimbursement_response(reimbursement)
    }, status: :created
  rescue Reimbursements::Conflict
    render json: { error: { code: "reimbursement_conflict", message: "The expense is not eligible for reimbursement or is already reimbursed." } }, status: :conflict
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_reimbursement", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "reimbursement_conflict", message: "A reimbursement already exists for this expense." } }, status: :conflict
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
    render json: { error: { code: "lock_version_required", message: "lock_version is required." } }, status: :unprocessable_entity
  end

  def render_stale_conflict
    @expense.reload
    render json: {
      error: {
        code: "stale_expense",
        message: "The expense changed since it was last read.",
        current_lock_version: @expense.lock_version
      }
    }, status: :conflict
  end

  def render_workflow_conflict(error)
    render json: { error: { code: "workflow_conflict", message: error.message.presence || "The expense is not in an actionable workflow state." } }, status: :conflict
  end

  def approval_response(approval)
    {
      id: approval.id,
      step: approval.step,
      stage: approval.stage,
      approver_membership_id: approval.approver_membership_id,
      status: approval.status,
      acted_at: approval.acted_at,
      rejection_reason: approval.rejection_reason
    }
  end

  def reimbursement_response(reimbursement)
    {
      id: reimbursement.id,
      expense_id: reimbursement.expense_id,
      initiated_by_membership_id: reimbursement.initiated_by_membership_id,
      amount: reimbursement.amount,
      currency: reimbursement.currency,
      status: reimbursement.status,
      paid_at: reimbursement.paid_at,
      failure_reason: reimbursement.failure_reason
    }
  end

  def expense_response(expense)
    {
      id: expense.id,
      team_id: expense.team_id,
      creator_membership_id: expense.creator_membership_id,
      member_membership_id: expense.member_membership_id,
      amount: expense.amount,
      currency: expense.currency,
      merchant: expense.merchant,
      description: expense.description,
      category: expense.category,
      incurred_on: expense.incurred_on,
      status: expense.status,
      lock_version: expense.lock_version,
      created_at: expense.created_at,
      updated_at: expense.updated_at
    }
  end
end