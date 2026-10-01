class ExpenseApprovalSerializer
  FIELDS = %i[id step stage approver_membership_id status acted_at rejection_reason].freeze

  def self.call(approval)
    FIELDS.to_h { |field| [field, approval.public_send(field)] }
  end
end