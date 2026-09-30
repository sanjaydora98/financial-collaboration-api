require "rails_helper"

RSpec.describe "Imported transaction review services" do
  def create_review_context
    requester = User.create!(email: "review-requester-#{SecureRandom.hex(4)}@example.com", name: "Requester", password: "password123")
    team, requester_membership = Teams::Create.call(
      user: requester,
      attributes: { name: "Review service", slug: "review-service-#{SecureRandom.hex(4)}" }
    )
    reviewer = User.create!(email: "reviewer-#{SecureRandom.hex(4)}@example.com", name: "Reviewer", password: "password123")
    reviewer_membership = TeamMembership.create!(team: team, user: reviewer, role: "approver", approval_stage: "manager")
    import = Import.create!(team: team, requested_by_membership: requester_membership, provider: "bank", idempotency_key: SecureRandom.hex(8), status: "completed")
    imported_transaction = ImportedTransaction.create!(
      team: team,
      import: import,
      provider: "bank",
      external_account_ref: "account-review",
      external_transaction_id: SecureRandom.hex(8),
      amount: 32.15,
      currency: "EUR",
      merchant: "Metro",
      description: "City transport",
      category: "Travel",
      transaction_date: Date.current
    )
    [requester, requester_membership, reviewer, reviewer_membership, import, imported_transaction]
  end

  it "rolls back expense creation, transaction acceptance, and audit if the acceptance audit fails" do
    _requester, _requester_membership, reviewer, _reviewer_membership, _import, imported_transaction = create_review_context
    allow(AuditLog).to receive(:create!).and_wrap_original do |original, attributes|
      raise ActiveRecord::RecordNotSaved if attributes[:event_type] == "import_accepted"

      original.call(attributes)
    end

    expect {
      ImportedTransactions::Accept.call(imported_transaction: imported_transaction, reviewer: reviewer)
    }.to raise_error(ActiveRecord::RecordNotSaved)

    expect(imported_transaction.reload).to have_attributes(status: "pending", reviewed_by_membership_id: nil, reviewed_at: nil)
    expect(imported_transaction.expense).to be_nil
    expect(AuditLog.where(expense_id: Expense.select(:id)).count).to eq(0)
  end

  it "uses the import requester for both expense membership fields and reviewer as the audit actor" do
    _requester, requester_membership, reviewer, reviewer_membership, _import, imported_transaction = create_review_context

    expense = ImportedTransactions::Accept.call(imported_transaction: imported_transaction, reviewer: reviewer)

    expect(expense).to have_attributes(
      creator_membership_id: requester_membership.id,
      member_membership_id: requester_membership.id,
      category: "Travel",
      amount: BigDecimal("32.15"),
      currency: "EUR"
    )
    expect(imported_transaction.reload.reviewed_by_membership_id).to eq(reviewer_membership.id)
    expect(expense.audit_logs.find_by!(event_type: "create").actor_membership_id).to eq(reviewer_membership.id)
    expect(expense.audit_logs.find_by!(event_type: "import_accepted").actor_membership_id).to eq(reviewer_membership.id)
  end

  it "does not infer a missing category" do
    _requester, _requester_membership, reviewer, _reviewer_membership, _import, imported_transaction = create_review_context
    imported_transaction.update!(category: nil)

    expense = ImportedTransactions::Accept.call(imported_transaction: imported_transaction, reviewer: reviewer)

    expect(expense.category).to be_nil
  end

  it "fails acceptance without a requester membership that remains active" do
    _requester, requester_membership, reviewer, _reviewer_membership, _import, imported_transaction = create_review_context
    requester_membership.update!(active: false)

    expect {
      ImportedTransactions::Accept.call(imported_transaction: imported_transaction, reviewer: reviewer)
    }.to raise_error(ActiveRecord::RecordNotFound)
    expect(imported_transaction.reload.status).to eq("pending")
    expect(imported_transaction.expense).to be_nil
  end

  it "rejects pending transactions without an audit row and retains the reviewer and reason" do
    _requester, _requester_membership, reviewer, reviewer_membership, _import, imported_transaction = create_review_context
    audits_before = AuditLog.count

    expect {
      ImportedTransactions::Reject.call(imported_transaction: imported_transaction, reviewer: reviewer, reason: "Duplicate charge")
    }.to change { imported_transaction.reload.status }.from("pending").to("rejected")
    expect(imported_transaction.reviewed_by_membership_id).to eq(reviewer_membership.id)
    expect(imported_transaction.rejection_reason).to eq("Duplicate charge")
    expect(imported_transaction.reviewed_at).to be_present
    expect(AuditLog.count).to eq(audits_before)
  end
end