# frozen_string_literal: true

module AuthConstants
  TOKEN_BYTES = 32
  SESSION_TTL = 24.hours
  TOKEN_PATTERN = /\ABearer ([A-Za-z0-9_-]{43})\z/.freeze
  ACTION_CABLE_TICKET_PURPOSE = "action_cable_connection"
  ACTION_CABLE_TICKET_TTL = 1.minute
end