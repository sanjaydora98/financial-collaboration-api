class ApplicationController < ActionController::API
  include Pundit::Authorization

  rescue_from StandardError, with: :render_unexpected_error
  rescue_from ActionController::BadRequest, with: :render_bad_request
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ActiveRecord::RecordNotSaved, with: :render_unprocessable_entity
  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_bad_request(_exception = nil)
    render_error(code: "bad_request", message: I18n.t("errors.request.bad_request"), status: :bad_request)
  end

  def render_forbidden(_exception = nil)
    render_error(code: "forbidden", message: I18n.t("errors.request.forbidden"), status: :forbidden)
  end

  def render_unprocessable_entity(_exception = nil)
    render_error(code: "unprocessable_entity", message: I18n.t("errors.request.unprocessable_entity"), status: :unprocessable_entity)
  end

  def render_not_found(_exception = nil)
    render_error(code: "not_found", message: I18n.t("errors.request.not_found"), status: :not_found)
  end

  def render_unexpected_error(exception)
    Rails.logger.error(
      "Unhandled request error request_id=#{request.request_id} user_id=#{current_user&.id} team_id=#{params[:team_id]} error_class=#{exception.class.name}"
    )
    render_error(code: "internal_server_error", message: I18n.t("errors.request.internal_server_error"), status: :internal_server_error)
  end

  def render_error(code:, message:, status:)
    render json: { error: { code: code, message: message } }, status: status
  end
end
