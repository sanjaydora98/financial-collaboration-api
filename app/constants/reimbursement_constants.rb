# frozen_string_literal: true

module ReimbursementConstants
  STATUSES = {
    pending: "pending",
    processing: "processing",
    paid: "paid",
    failed: "failed",
    cancelled: "cancelled"
  }.freeze
end