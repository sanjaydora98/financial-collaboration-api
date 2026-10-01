# frozen_string_literal: true

require "rails_helper"

# Regression check: every I18n.t("...") literal key referenced from application
# code must resolve to an actual translation in config/locales. This is what
# would have caught the missing `errors.team.not_found` key before it reached
# a running server. It is intentionally static (no interpolation is
# performed) so it only verifies key *existence*, not formatting.
RSpec.describe "I18n keys", type: :static_check do
  LOOKUP_PATTERN = /I18n\.t\(\s*["']([a-zA-Z0-9_.]+)["']/.freeze

  def referenced_keys
    Dir.glob(Rails.root.join("app/**/*.rb")).each_with_object({}) do |path, keys|
      File.readlines(path).each_with_index do |line, index|
        line.scan(LOOKUP_PATTERN).each do |(key)|
          keys[key] ||= []
          keys[key] << "#{path.sub(Rails.root.to_s + '/', '')}:#{index + 1}"
        end
      end
    end
  end

  it "has a translation for every I18n.t key referenced in app/" do
    missing = referenced_keys.reject { |key, _locations| I18n.exists?(key, :en) }

    message = missing.map { |key, locations| "#{key} (used at #{locations.join(', ')})" }.join("\n")
    expect(missing).to be_empty, "Missing I18n translations for:\n#{message}"
  end

  it "resolves every AuditLog errors.add(:attribute, :symbol) validation message" do
    # AuditLog#event_type_matches_category raises a symbol-based error; make sure it
    # does not fall through to ActiveModel's "Translation missing" placeholder.
    log = AuditLog.new(actor_type: AuditConstants::ACTOR_TYPES[:user], category: AuditConstants::CATEGORIES[:crud], event_type: "not-a-real-event")
    log.valid?

    expect(log.errors.full_messages.join(" ")).not_to include("Translation missing")
  end
end
