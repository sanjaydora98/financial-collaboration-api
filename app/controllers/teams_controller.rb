class TeamsController < ApplicationController
  include BearerAuthentication

  before_action :authenticate_request!
  before_action :set_team, only: %i[show bootstrap_admin]

  def index
    teams = policy_scope(Team).to_a
    memberships_by_team = current_user.team_memberships.where(team_id: teams.map(&:id), active: true).index_by(&:team_id)
    render json: { teams: teams.map { |team| TeamSerializer.call(team, membership: memberships_by_team[team.id]) } }, status: :ok
  end

  def create
    team = Team.new
    authorize team, :create?

    created_team, membership = Teams::Create.call(user: current_user, attributes: team_params)
    render json: { team: TeamSerializer.call(created_team, membership: membership) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_team", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "team_conflict", message: I18n.t("errors.team.conflict") } }, status: :conflict
  end

  def show
    authorize @team, :show?
    membership = current_user.team_memberships.find_by(team_id: @team.id, active: true)
    render json: { team: TeamSerializer.call(@team, membership: membership) }, status: :ok
  end

  def bootstrap_admin
    membership = @team.team_memberships.find_by!(user_id: current_user.id)
    authorize membership, :bootstrap_admin?
    promoted = Teams::PromoteCreatorToAdmin.call(team: @team, membership: membership, user: current_user)
    render json: { membership: TeamMembershipSerializer.call(promoted) }, status: :ok
  end

  private

  def set_team
    @team = policy_scope(Team).find(params[:id] || params[:team_id])
  end

  def team_params
    params.fetch(:team, ActionController::Parameters.new).permit(:name, :slug)
  end

end