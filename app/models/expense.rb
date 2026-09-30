class Expense < ApplicationRecord
  STATUSES = %w[draft submitted approved rejected reimbursed].freeze
  AUDIT_IGNORED_ATTRIBUTES = %w[created_at updated_at lock_version].freeze

  enum :status, STATUSES.index_with(&:itself)

  scope :not_deleted, -> { where(deleted_at: nil) }

  belongs_to :team
  belongs_to :creator_membership, class_name: "TeamMembership", inverse_of: :created_expenses
  belongs_to :member_membership, class_name: "TeamMembership", inverse_of: :member_expenses
  belongs_to :imported_transaction, optional: true, inverse_of: :expense

  has_many :expense_approvals, dependent: :restrict_with_exception
  has_many :audit_logs, dependent: :restrict_with_exception
  has_one :reimbursement, dependent: :restrict_with_exception

  attr_accessor :audit_actor_membership_id

  before_destroy { throw(:abort) }
  after_create :record_crud_audit
  after_update :record_crud_audit

  validates :amount, numericality: { greater_than: 0 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :merchant, :incurred_on, presence: true
  validates :status, presence: true
  validates :description, length: { maximum: 10_000 }, allow_nil: true
  validates :category, length: { maximum: 100 }, allow_nil: true

  private

  def record_crud_audit
    event_type = if previously_new_record?
      "create"
    elsif saved_change_to_deleted_at? && deleted_at.present?
      "delete"
    else
      "update"
    end

    audited_changes = saved_changes.except(*AUDIT_IGNORED_ATTRIBUTES)
    before_values = audited_changes.transform_values(&:first)
    after_values = audited_changes.transform_values(&:last)

    if event_type == "create"
      before_values = {}
    end

    audit_logs.create!(
      team_id: team_id,
      actor_membership_id: audit_actor_membership_id,
      actor_type: audit_actor_membership_id.present? ? "user" : "system",
      category: "crud",
      event_type: event_type,
      change_data: { before: before_values, after: after_values }
    )
  end
end