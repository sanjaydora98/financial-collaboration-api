class AuditLog < ApplicationRecord
  belongs_to :team
  belongs_to :expense, inverse_of: :audit_logs
  belongs_to :actor_membership, class_name: "TeamMembership", optional: true, inverse_of: :audit_logs

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }
  after_commit :publish_realtime_event, on: :create

  validates :actor_type, inclusion: { in: AuditConstants::ACTOR_TYPES.values }
  validates :category, inclusion: { in: AuditConstants::CATEGORIES.values }
  validates :event_type, presence: true
  validate :event_type_matches_category
  validate :actor_matches_type

  private

  def publish_realtime_event
    Realtime::AuditEventPublisher.call(self)
  end

  def event_type_matches_category
    allowed = AuditConstants::EVENTS_BY_CATEGORY[category]
    return if allowed&.include?(event_type)

    errors.add(:event_type, :invalid_for_category)
  end

  def actor_matches_type
    if actor_type == AuditConstants::ACTOR_TYPES[:user] && actor_membership_id.blank?
      errors.add(:actor_membership, "must be present for user events")
    elsif actor_type == AuditConstants::ACTOR_TYPES[:system] && actor_membership_id.present?
      errors.add(:actor_membership, "must be blank for system events")
    end
  end
end