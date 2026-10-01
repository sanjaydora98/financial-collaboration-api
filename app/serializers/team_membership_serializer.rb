class TeamMembershipSerializer
  FIELDS = %i[id public_id user_id role approval_stage active].freeze

  def self.call(membership)
    FIELDS.to_h { |field| [field, membership.public_send(field)] }.merge(
      user: { name: membership.user.name, email: membership.user.email },
      status: membership.active? ? "active" : "inactive"
    )
  end
end