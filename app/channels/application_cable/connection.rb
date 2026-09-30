module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_auth_session

    def connect
      self.current_auth_session = Authentication::SessionAuthenticator.call(request.headers["Authorization"])
      reject_unauthorized_connection unless current_auth_session

      self.current_user = current_auth_session.user
      current_auth_session.update_column(:last_used_at, Time.current)
    end
  end
end
