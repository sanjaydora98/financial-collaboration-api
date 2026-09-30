class Import < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze

  enum :status, STATUSES.index_with(&:itself)

  belongs_to :team
  belongs_to :requested_by_membership, class_name: "TeamMembership", inverse_of: :requested_imports
  has_many :imported_transactions, dependent: :restrict_with_exception

  after_commit :publish_realtime_status, on: %i[create update]

  validates :provider, :idempotency_key, presence: true
  validates :status, presence: true

  private

  def publish_realtime_status
    return unless saved_change_to_status?

    Realtime::Publisher.publish(
      team_id: team_id,
      event: "import.updated",
      resource: {
        id: id,
        status: status,
        started_at: started_at,
        finished_at: finished_at,
        imported_transaction_count: imported_transactions.count
      }
    )
  end
end