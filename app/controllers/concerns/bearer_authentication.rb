module BearerAuthentication
  extend ActiveSupport::Concern

  attr_reader :current_auth_session

  private

  def authenticate_request!
    session = Authentication::SessionAuthenticator.call(request.headers["Authorization"])

    unless session
      return render json: { error: { code: "unauthorized", message: I18n.t("errors.authentication.required") } }, status: :unauthorized
    end

    @current_auth_session = session
    @current_user = session.user
    session.update_column(:last_used_at, Time.current)
  end

  def current_user
    @current_user
  end
end