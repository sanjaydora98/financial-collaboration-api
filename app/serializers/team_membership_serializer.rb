class TeamMembershipSerializer
  FIELDS = %i[id user_id role approval_stage active].freeze

  def self.call(membership)
    FIELDS.to_h { |field| [field, membership.public_send(field)] }
  end
end