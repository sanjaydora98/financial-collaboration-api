require "rails_helper"

RSpec.describe "Import services" do
  def create_context
    requester = User.create!(email: "import-service-#{SecureRandom.hex(4)}@example.com", name: "Requester", password: "password123")
    team, membership = Teams::Create.call(
      user: requester,
      attributes: { name: "Import service", slug: "import-service-#{SecureRandom.hex(4)}" }
    )
    import = Import.create!(team: team, requested_by_membership: membership, provider: "bank", idempotency_key: "key-#{SecureRandom.hex(4)}")
    payload = {
      external_account_ref: "account-service",
      external_transaction_id: "transaction-service",
      amount: 24.60,
      currency: "USD",
      merchant: "Taxi",
      description: "Airport trip",
      category: "Travel",
      transaction_date: Date.current
    }
    [requester, team, membership, import, payload]
  end

  it "processes external rows idempotently and preserves category" do
    _requester, _team, _membership, import, payload = create_context

    2.times { Imports::Process.call(import: import, transactions: [payload, payload]) }

    expect(import.reload.status).to eq("completed")
    expect(import.imported_transactions.count).to eq(1)
    expect(import.imported_transactions.first).to have_attributes(status: "pending", category: "Travel")
  end

  it "marks processing failed and leaves no partial transaction rows on validation failure" do
    _requester, _team, _membership, import, payload = create_context

    expect {
      Imports::Process.call(import: import, transactions: [payload, payload.merge(amount: 0)])
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(import.reload).to have_attributes(status: "failed")
    expect(import.error_summary).to be_present
    expect(import.imported_transactions.count).to eq(0)
  end
end