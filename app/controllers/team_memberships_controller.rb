class TeamMembershipsController < ApplicationController
  include BearerAuthentication

  before_action :authenticate_request!
  before_action :set_team
  before_action :set_membership, only: %i[update destroy]

  def index
    membership = TeamMembership.new(team: @team)
    authorize membership, :index?
    memberships = @team.team_memberships
    memberships = memberships.where(active: true) unless current_user.team_memberships.exists?(team_id: @team.id, role: "admin", active: true)
    render json: { memberships: memberships.order(:id).map { |item| membership_response(item) } }, status: :ok
  end

  def create
    membership = TeamMembership.new(team: @team)
    authorize membership, :create?
    created = TeamMemberships::Create.call(team: @team, attributes: membership_params)
    render json: { membership: membership_response(created) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_membership", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "membership_conflict", message: "The user already has a membership in this team or the approval stage is occupied." } }, status: :conflict
  end

  def update
    authorize @membership, :update?
    updated = TeamMemberships::Update.call(team: @team, membership: @membership, attributes: update_params)
    render json: { membership: membership_response(updated) }, status: :ok
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_membership", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "membership_conflict", message: "The approval stage is occupied." } }, status: :conflict
  rescue TeamMemberships::Update::LastActiveAdminError
    render json: { error: { code: "last_admin_required", message: "A team must retain an active admin." } }, status: :conflict
  end

  def destroy
    authorize @membership, :destroy?
    deactivated = TeamMemberships::Update.call(team: @team, membership: @membership, attributes: { active: false })
    render json: { membership: membership_response(deactivated) }, status: :ok
  rescue TeamMemberships::Update::LastActiveAdminError
    render json: { error: { code: "last_admin_required", message: "A team must retain an active admin." } }, status: :conflict
  end

  private

  def set_team
    @team = policy_scope(Team).find(params[:team_id])
  end

  def set_membership
    @membership = @team.team_memberships.find(params[:id])
  end

  def membership_params
    params.fetch(:membership, ActionController::Parameters.new).permit(:user_id, :role, :approval_stage)
  end

  def update_params
    params.fetch(:membership, ActionController::Parameters.new).permit(:role, :approval_stage, :active).to_h.symbolize_keys
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