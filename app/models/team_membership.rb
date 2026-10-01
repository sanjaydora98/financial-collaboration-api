class TeamMembership < ApplicationRecord
  enum :role, MembershipConstants::ROLES

  enum :approval_stage, MembershipConstants::APPROVAL_STAGES, prefix: true

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
  validates :public_id, presence: true, uniqueness: true
  before_validation :assign_public_id, on: :create
  validate :approval_stage_matches_role

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def approval_stage_matches_role
    allowed = case role
    when MembershipConstants::ROLES[:approver]
      MembershipConstants::APPROVAL_STAGES.values
    when MembershipConstants::ROLES[:admin]
      [nil, *MembershipConstants::APPROVAL_STAGES.values]
    else
      [nil]
    end

    errors.add(:approval_stage, "is not valid for this role") unless allowed.include?(approval_stage)
  end
end