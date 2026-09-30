class ImportsController < ApplicationController
  include BearerAuthentication

  before_action :authenticate_request!
  before_action :set_team
  before_action :set_import, only: :show

  def index
    import = Import.new(team: @team)
    authorize import, :index?
    imports = policy_scope(@team.imports).order(created_at: :desc, id: :desc)
    render json: { imports: imports.map { |record| import_response(record) } }, status: :ok
  end

  def create
    current_membership = @team.team_memberships.find_by!(user_id: current_user.id, active: true)
    candidate = Import.new(team: @team, requested_by_membership: current_membership)
    authorize candidate, :create?
    attributes = import_params
    result = Imports::Request.call(
      team: @team,
      requested_by_membership: current_membership,
      provider: attributes[:provider],
      idempotency_key: attributes[:idempotency_key],
      transactions: attributes[:transactions]
    )
    render json: { import: import_response(result.import), job_id: result.job_id }, status: result.created ? :accepted : :ok
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_import", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "import_conflict", message: "The import request conflicts with an existing idempotency key." } }, status: :conflict
  end

  def show
    authorize @import, :show?
    render json: { import: import_response(@import) }, status: :ok
  end

  private

  def set_team
    @team = policy_scope(Team).find(params[:team_id])
  end

  def set_import
    @import = @team.imports.find(params[:id])
  end

  def import_params
    params.fetch(:import, ActionController::Parameters.new).permit(
      :provider,
      :idempotency_key,
      transactions: %i[external_account_ref external_transaction_id amount currency merchant description category transaction_date]
    ).to_h.symbolize_keys
  end

  def import_response(import)
    {
      id: import.id,
      team_id: import.team_id,
      requested_by_membership_id: import.requested_by_membership_id,
      provider: import.provider,
      idempotency_key: import.idempotency_key,
      status: import.status,
      started_at: import.started_at,
      finished_at: import.finished_at,
      error_summary: import.error_summary,
      imported_transaction_count: import.imported_transactions.count
    }
  end
end