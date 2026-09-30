class ExpenseApproval < ApplicationRecord
  STAGES = %w[manager finance].freeze
  STATUSES = %w[queued pending approved rejected skipped].freeze

  enum :stage, STAGES.index_with(&:itself)
  enum :status, STATUSES.index_with(&:itself)

  belongs_to :team
  belongs_to :expense, inverse_of: :expense_approvals
  belongs_to :approver_membership, class_name: "TeamMembership", inverse_of: :expense_approvals

  validates :step, numericality: { only_integer: true, greater_than: 0 }
  validates :stage, :status, presence: true
  validates :rejection_reason, presence: true, if: :rejected?
  validate :step_matches_stage
  validate :decision_timestamp_matches_status
  validate :rejection_reason_absent_unless_rejected

  private

  def step_matches_stage
    expected = { "manager" => 1, "finance" => 2 }[stage]
    errors.add(:step, "does not match stage") if expected && step != expected
  end

  def decision_timestamp_matches_status
    decided = approved? || rejected? || skipped?
    errors.add(:acted_at, "must be present for a decided approval") if decided && acted_at.blank?
    errors.add(:acted_at, "must be blank for a pending approval") if (queued? || pending?) && acted_at.present?
  end

  def rejection_reason_absent_unless_rejected
    errors.add(:rejection_reason, "must be blank unless rejected") if !rejected? && rejection_reason.present?
  end
end