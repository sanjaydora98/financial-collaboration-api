# frozen_string_literal: true

module MembershipConstants
  ROLES = {
    creator: "creator",
    approver: "approver",
    viewer: "viewer",
    admin: "admin"
  }.freeze
  EXPENSE_VISIBILITY_ROLES = [ROLES[:admin], ROLES[:approver], ROLES[:viewer]].freeze

  APPROVAL_STAGES = {
    manager: "manager",
    finance: "finance"
  }.freeze
end