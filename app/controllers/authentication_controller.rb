class AuthenticationController < ApplicationController
  include BearerAuthentication

  before_action :authenticate_request!, only: %i[cable_ticket me logout]

  def register
    user, credentials = Authentication::RegisterUser.call(registration_params)
    render json: authentication_response(user, credentials), status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: { code: "invalid_registration", details: error.record.errors.to_hash } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: { code: "invalid_registration", message: I18n.t("errors.authentication.email_taken") } }, status: :unprocessable_entity
  end

  def login
    credentials = login_params
    if credentials[:email].blank? || credentials[:password].blank?
      return render json: { error: { code: "invalid_credentials_input", message: I18n.t("errors.authentication.credentials_required") } }, status: :unprocessable_entity
    end

    result = Authentication::AuthenticateUser.call(email: credentials[:email], password: credentials[:password])
    return invalid_credentials unless result

    user, session_credentials = result
    render json: authentication_response(user, session_credentials), status: :ok
  end

  def me
    render json: { user: user_response(current_user) }, status: :ok
  end

  def cable_ticket
    ticket = Authentication::ActionCableTicket.issue(session: current_auth_session)
    render json: { ticket: ticket }, status: :ok
  end

  def logout
    current_auth_session.update!(revoked_at: Time.current)
    head :no_content
  end

  private

  def registration_params
    params.fetch(:user, ActionController::Parameters.new).permit(:email, :name, :password, :password_confirmation)
  end

  def login_params
    params.permit(:email, :password)
  end

  def invalid_credentials
    render json: { error: { code: "invalid_credentials", message: I18n.t("errors.authentication.credentials_invalid") } }, status: :unauthorized
  end

  def authentication_response(user, credentials)
    {
      user: user_response(user),
      token: credentials.token,
      expires_at: credentials.session.expires_at
    }
  end

  def user_response(user)
    UserSerializer.call(user)
  end
end