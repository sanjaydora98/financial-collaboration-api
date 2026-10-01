class ReimbursementSerializer
  FIELDS = %i[
    id expense_id initiated_by_membership_id amount currency status paid_at failure_reason
  ].freeze

  def self.call(reimbursement)
    FIELDS.to_h { |field| [field, reimbursement.public_send(field)] }
  end
end