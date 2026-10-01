# frozen_string_literal: true

module ApprovalConstants
  STAGES = MembershipConstants::APPROVAL_STAGES

  STATUSES = {
    queued: "queued",
    pending: "pending",
    approved: "approved",
    rejected: "rejected",
    skipped: "skipped"
  }.freeze

  DECISIONS = {
    approve: "approve",
    reject: "reject"
  }.freeze

  DECISION_STATUSES = {
    DECISIONS[:approve] => STATUSES[:approved],
    DECISIONS[:reject] => STATUSES[:rejected]
  }.freeze

  STAGE_STEPS = {
    STAGES[:manager] => 1,
    STAGES[:finance] => 2
  }.freeze

  INITIAL_STEPS = [
    { step: STAGE_STEPS[STAGES[:manager]], stage: STAGES[:manager], status: STATUSES[:pending] }.freeze,
    { step: STAGE_STEPS[STAGES[:finance]], stage: STAGES[:finance], status: STATUSES[:queued] }.freeze
  ].freeze
end