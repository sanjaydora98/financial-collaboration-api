class AuditLog < ApplicationRecord
  CATEGORIES = %w[crud workflow].freeze
  CRUD_EVENTS = %w[create update delete].freeze
  WORKFLOW_EVENTS = %w[submitted approved rejected reimbursement_paid import_accepted reimbursement_initiated reimbursement_failed].freeze

  belongs_to :team
  belongs_to :expense, inverse_of: :audit_logs
  belongs_to :actor_membership, class_name: "TeamMembership", optional: true, inverse_of: :audit_logs

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }
  after_commit :publish_realtime_event, on: :create

  validates :actor_type, inclusion: { in: %w[user system] }
  validates :category, inclusion: { in: CATEGORIES }
  validates :event_type, presence: true
  validate :event_type_matches_category
  validate :actor_matches_type

  private

  def publish_realtime_event
    Realtime::AuditEventPublisher.call(self)
  end

  def event_type_matches_category
    allowed = category == "crud" ? CRUD_EVENTS : WORKFLOW_EVENTS
    errors.add(:event_type, "is not valid for category") unless allowed.include?(event_type)
  end

  def actor_matches_type
    if actor_type == "user" && actor_membership_id.blank?
      errors.add(:actor_membership, "must be present for user events")
    elsif actor_type == "system" && actor_membership_id.present?
      errors.add(:actor_membership, "must be blank for system events")
    end
  end
end