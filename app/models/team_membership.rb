class TeamMembership < ApplicationRecord
  enum :role, {
    creator: "creator",
    approver: "approver",
    viewer: "viewer",
    admin: "admin"
  }

  enum :approval_stage, {
    manager: "manager",
    finance: "finance"
  }, prefix: true

  belongs_to :team
  belongs_to :user

  has_many :created_expenses, class_name: "Expense", foreign_key: :creator_membership_id, inverse_of: :creator_membership, dependent: :restrict_with_exception
  has_many :member_expenses, class_name: "Expense", foreign_key: :member_membership_id, inverse_of: :member_membership, dependent: :restrict_with_exception
  has_many :expense_approvals, foreign_key: :approver_membership_id, inverse_of: :approver_membership, dependent: :restrict_with_exception
  has_many :initiated_reimbursements, class_name: "Reimbursement", foreign_key: :initiated_by_membership_id, inverse_of: :initiated_by_membership, dependent: :restrict_with_exception
  has_many :audit_logs, foreign_key: :actor_membership_id, inverse_of: :actor_membership, dependent: :restrict_with_exception
  has_many :requested_imports, class_name: "Import", foreign_key: :requested_by_membership_id, inverse_of: :requested_by_membership, dependent: :restrict_with_exception
  has_many :reviewed_imported_transactions, class_name: "ImportedTransaction", foreign_key: :reviewed_by_membership_id, inverse_of: :reviewed_by_membership, dependent: :restrict_with_exception

  validates :role, presence: true
  validate :approval_stage_matches_role

  private

  def approval_stage_matches_role
    allowed = case role
    when "approver"
      %w[manager finance]
    when "admin"
      [nil, "manager", "finance"]
    else
      [nil]
    end

    errors.add(:approval_stage, "is not valid for this role") unless allowed.include?(approval_stage)
  end
end