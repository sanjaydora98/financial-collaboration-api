class ImportedTransaction < ApplicationRecord
  STATUSES = %w[pending accepted rejected].freeze

  enum :status, STATUSES.index_with(&:itself)

  belongs_to :team
  belongs_to :import, inverse_of: :imported_transactions
  belongs_to :reviewed_by_membership, class_name: "TeamMembership", optional: true, inverse_of: :reviewed_imported_transactions
  has_one :expense, inverse_of: :imported_transaction, dependent: :restrict_with_exception

  after_commit :publish_rejection, on: :update

  validates :provider, :external_account_ref, :external_transaction_id, :merchant, :transaction_date, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :category, length: { maximum: 100 }, allow_nil: true
  validates :status, presence: true
  validates :reviewed_at, absence: true, if: :pending?
  validates :reviewed_by_membership, absence: true, if: :pending?
  validates :reviewed_at, presence: true, unless: :pending?
  validates :reviewed_by_membership, presence: true, unless: :pending?
  validates :rejection_reason, presence: true, if: :rejected?
  validates :rejection_reason, absence: true, unless: :rejected?

  private

  def publish_rejection
    return unless saved_change_to_status? && rejected?

    Realtime::Publisher.publish(
      team_id: team_id,
      event: "imported_transaction.rejected",
      resource: {
        id: id,
        status: status,
        reviewed_by_membership_id: reviewed_by_membership_id,
        reviewed_at: reviewed_at,
        rejection_reason: rejection_reason
      }
    )
  end
end