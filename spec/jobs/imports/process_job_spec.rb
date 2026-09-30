require "rails_helper"

RSpec.describe Imports::ProcessJob do
  before { described_class.clear }

  def create_import(key: SecureRandom.hex(8))
    user = User.create!(email: "job-requester-#{SecureRandom.hex(4)}@example.com", name: "Requester", password: "password123")
    team, membership = Teams::Create.call(user: user, attributes: { name: "Job import", slug: "job-import-#{SecureRandom.hex(4)}" })
    import = Import.create!(team: team, requested_by_membership: membership, provider: "bank", idempotency_key: key)
    [import, team]
  end

  def transaction_payload(external_id: SecureRandom.hex(8))
    {
      external_account_ref: "job-account",
      external_transaction_id: external_id,
      amount: "15.20",
      currency: "USD",
      merchant: "Job merchant",
      transaction_date: Date.current.to_s,
      category: "Travel"
    }
  end

  it "is enqueued with a stable Import ID and JSON-safe permitted payload" do
    _unused_import, team = create_import
    membership = team.team_memberships.find_by!(role: "creator")
    payload = transaction_payload
    result = Imports::Request.call(
      team: team,
      requested_by_membership: membership,
      provider: "bank",
      idempotency_key: "request-#{SecureRandom.hex(4)}",
      transactions: [payload]
    )

    expect(result.job_id).to be_present
    expect(described_class.jobs.length).to eq(1)
    job = described_class.jobs.first
    expect(job.fetch("args").first).to eq(result.import.id)
    expect(job.fetch("args").last.first).to include("external_transaction_id", "category")
    expect(job.fetch("args").last.first).not_to include("password", "token", "raw_payload")
    expect(described_class.get_sidekiq_options["retry"]).to eq(5)
  end

  it "loads the Import by ID and processes it through Imports::Process" do
    import, team = create_import
    payload = transaction_payload

    described_class.new.perform(import.id, [payload])

    expect(import.reload.status).to eq("completed")
    expect(ImportedTransaction.where(team: team).pluck(:external_transaction_id)).to eq([payload[:external_transaction_id]])
  end

  it "is safe when the same job is executed twice" do
    import, = create_import
    payload = transaction_payload
    described_class.new.perform(import.id, [payload])

    described_class.new.perform(import.id, [payload])

    expect(import.reload.status).to eq("completed")
    expect(import.imported_transactions.count).to eq(1)
  end

  it "rolls back partial batch inserts on failure and safely retries the same payload" do
    import, = create_import
    row = transaction_payload
    payload = [row, row.dup]
    failed_once = false
    allow_any_instance_of(Import).to receive(:update!).and_wrap_original do |original, *arguments|
      attributes = arguments.first || {}
      if attributes[:status] == "completed" && !failed_once
        failed_once = true
        raise "simulated crash after row insertion"
      end
      original.call(*arguments)
    end

    expect { described_class.new.perform(import.id, payload) }.to raise_error("simulated crash after row insertion")
    expect(import.reload.status).to eq("failed")
    expect(import.imported_transactions.count).to eq(0)

    described_class.new.perform(import.id, payload)

    expect(import.reload.status).to eq("completed")
    expect(import.imported_transactions.count).to eq(1)
  end
end