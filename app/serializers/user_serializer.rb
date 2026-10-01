class UserSerializer
  FIELDS = %i[id email name].freeze

  def self.call(user)
    FIELDS.to_h { |field| [field, user.public_send(field)] }
  end
end