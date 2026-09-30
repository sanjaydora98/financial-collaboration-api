class TeamsController < ApplicationController
  include BearerAuthentication

  before_action :authenticate_request!
  before_action :set_team, only: %i[show bootstrap_admin]

  def index
    teams = policy_scope(Team).includes(:team_memberships)
    render json: { teams: teams.map { |team| team_response(team) } }, status: :ok
  end

  def create
    team = Team.new
    authorize team, :create?

    created_team, membership = Teams::Create.call(user: current_user, attributes: team_params)
    render json: { team: team_response(created_team, membership) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_team", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "team_conflict", message: "Team slug is already in use." } }, status: :conflict
  end

  def show
    authorize @team, :show?
    render json: { team: team_response(@team) }, status: :ok
  end

  def bootstrap_admin
    membership = @team.team_memberships.find_by!(user_id: current_user.id)
    authorize membership, :bootstrap_admin?
    promoted = Teams::PromoteCreatorToAdmin.call(team: @team, membership: membership, user: current_user)
    render json: { membership: membership_response(promoted) }, status: :ok
  end

  private

  def set_team
    @team = policy_scope(Team).find(params[:id] || params[:team_id])
  end

  def team_params
    params.fetch(:team, ActionController::Parameters.new).permit(:name, :slug)
  end

  def team_response(team, membership = nil)
    membership ||= current_user.team_memberships.find_by(team_id: team.id, active: true)
    {
      id: team.id,
      name: team.name,
      slug: team.slug,
      created_by_id: team.created_by_id,
      membership: membership && membership_response(membership)
    }
  end

  def membership_response(membership)
    {
      id: membership.id,
      user_id: membership.user_id,
      role: membership.role,
      approval_stage: membership.approval_stage,
      active: membership.active
    }
  end
end