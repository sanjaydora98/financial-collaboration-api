class Reimbursement < ApplicationRecord
  enum :status, ReimbursementConstants::STATUSES

  belongs_to :team
  belongs_to :expense, inverse_of: :reimbursement
  belongs_to :initiated_by_membership, class_name: "TeamMembership", inverse_of: :initiated_reimbursements

  validates :amount, numericality: { greater_than: 0 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :status, presence: true
  validates :paid_at, presence: true, if: :paid?
  validates :paid_at, absence: true, unless: :paid?
  validates :failure_reason, presence: true, if: :failed?
  validates :failure_reason, absence: true, unless: :failed?
  validate :matches_full_expense_amount_and_currency

  private

  def matches_full_expense_amount_and_currency
    return unless expense && amount && currency

    errors.add(:amount, "must match the full expense amount") unless amount == expense.amount
    errors.add(:currency, "must match the expense currency") unless currency == expense.currency
  end
end