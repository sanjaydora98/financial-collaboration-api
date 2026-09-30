module Authentication
  class RegisterUser
    def self.call(attributes)
      User.transaction do
        user = User.create!(attributes)
        [user, SessionIssuer.call(user: user)]
      end
    end
  end
end