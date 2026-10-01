require "rails_helper"

RSpec.describe "Imports API", type: :request do
  before do
    Imports::ProcessJob.clear
    setup_import_context
  end

  def create_user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  def headers_for(user)
    { "Authorization" => "Bearer #{Authentication::SessionIssuer.call(user: user).token}" }
  end

  def setup_import_context
    @requester = create_user("import-requester-#{SecureRandom.hex(4)}@example.com")
    @team, @requester_membership = Teams::Create.call(
      user: @requester,
      attributes: { name: "Import team", slug: "import-team-#{SecureRandom.hex(4)}" }
    )
    @admin = create_user("import-admin-#{SecureRandom.hex(4)}@example.com")
    @admin_membership = TeamMembership.create!(team: @team, user: @admin, role: "admin")
    @approver = create_user("import-approver-#{SecureRandom.hex(4)}@example.com")
    @approver_membership = TeamMembership.create!(team: @team, user: @approver, role: "approver", approval_stage: "manager")
    @viewer = create_user("import-viewer-#{SecureRandom.hex(4)}@example.com")
    TeamMembership.create!(team: @team, user: @viewer, role: "viewer")
    @payload = {
      external_account_ref: "account-123",
      external_transaction_id: "transaction-123",
      amount: "72.35",
      currency: "USD",
      merchant: "Railway",
      description: "Regional fare",
      category: "Travel",
      transaction_date: Date.current.to_s
    }
  end

  def create_import(user: @requester, team: @team, provider: "bank", key: "request-1", transactions: [@payload])
    post "/teams/#{team.id}/imports",
      params: { import: { provider: provider, idempotency_key: key, transactions: transactions } },
      headers: headers_for(user), as: :json
    @last_import_id = JSON.parse(response.body).dig("import", "id") if response.body.present? && response.status.in?([200, 201, 202])
  end

  def perform_import_jobs(import_id)
    jobs = Imports::ProcessJob.jobs.select { |job| job.fetch("args").first.to_i == import_id }.dup
    jobs.each do |job|
      Imports::ProcessJob.new.perform(*job.fetch("args"))
      Imports::ProcessJob.jobs.delete(job)
    end
  end

  def import_id
    @last_import_id
  end

  def json
    JSON.parse(response.body)
  end

  def imported_transaction_path(import_id, transaction_id, action)
    "/teams/#{@team.id}/imports/#{import_id}/imported_transactions/#{transaction_id}/#{action}"
  end

  it "creates an import and processes multiple transactions to pending review" do
    transactions = [@payload, @payload.merge(external_transaction_id: "transaction-456")]
    expect { create_import(transactions: transactions) }.to change(Import, :count).by(1).and change(ImportedTransaction, :count).by(0)

    expect(response).to have_http_status(:accepted)
    import = Import.find(import_id)
    expect(import).to have_attributes(status: "queued", requested_by_membership_id: @requester_membership.id, provider: "bank")
    expect(Imports::ProcessJob.jobs.size).to eq(1)

    perform_import_jobs(import.id)
    import.reload
    expect(import.status).to eq("completed")
    expect(import.started_at).to be_present
    expect(import.finished_at).to be_present
    expect(import.imported_transactions.pluck(:status).uniq).to eq(["pending"])
    expect(import.imported_transactions.count).to eq(2)
  end

  it "requires authentication and an active non-viewer membership to start an import" do
    post "/teams/#{@team.id}/imports", params: { import: { provider: "bank", idempotency_key: "unauth" } }, as: :json
    expect(response).to have_http_status(:unauthorized)

    expect { create_import(user: @viewer, key: "viewer-request") }.not_to change(Import, :count)
    expect(response).to have_http_status(:forbidden)

    @requester_membership.update!(active: false)
    create_import(user: @requester, key: "inactive-request")
    expect(response).to have_http_status(:not_found)
  end

  it "returns the existing Import for a repeated team/provider/idempotency key" do
    create_import(key: "stable-key")
    first_id = import_id

    expect { create_import(key: "stable-key", transactions: [@payload, @payload]) }.not_to change(Import, :count)
    expect(response).to have_http_status(:ok)
    expect(import_id).to eq(first_id)
    perform_import_jobs(first_id.to_i)
    expect(ImportedTransaction.count).to eq(1)
  end

  it "deduplicates repeated external transactions in a payload and preserves the first row" do
    create_import(key: "duplicates", transactions: [@payload, @payload.merge(description: "changed replay")])

    expect(response).to have_http_status(:accepted)
    perform_import_jobs(import_id.to_i)
    expect(ImportedTransaction.count).to eq(1)
    expect(ImportedTransaction.first.description).to eq("Regional fare")
  end

  it "persists category as a nullable varchar matching the expense convention" do
    category_column = ActiveRecord::Base.connection.columns(:imported_transactions).find { |column| column.name == "category" }

    expect(category_column).to be_present
    expect(category_column.type).to eq(:string)
    expect(category_column.null).to be(true)
    expect(category_column.limit).to be_nil
  end

  it "keeps external identity scoped by team and provider" do
    create_import(key: "same-team-default")
    perform_import_jobs(import_id.to_i)
    first_transaction_id = ImportedTransaction.first.id

    create_import(provider: "another-bank", key: "another-provider")
    expect(response).to have_http_status(:accepted)
    perform_import_jobs(import_id.to_i)
    expect(ImportedTransaction.where(external_transaction_id: "transaction-123").count).to eq(2)

    another_user = create_user("second-import-team@example.com")
    other_team, = Teams::Create.call(user: another_user, attributes: { name: "Other import team", slug: "other-import-#{SecureRandom.hex(4)}" })
    create_import(user: another_user, team: other_team, key: "other-team")
    expect(response).to have_http_status(:accepted)
    perform_import_jobs(import_id.to_i)
    expect(ImportedTransaction.where(external_transaction_id: "transaction-123").count).to eq(3)
    expect(ImportedTransaction.find(first_transaction_id).team_id).to eq(@team.id)
  end

  it "marks a malformed import failed and rolls back its transaction rows" do
    invalid_payload = @payload.merge(amount: "0")

    expect { create_import(key: "invalid", transactions: [@payload, invalid_payload]) }.to change(Import, :count).by(1)

    expect(response).to have_http_status(:accepted)
    import = Import.order(:id).last
    expect {
      perform_import_jobs(import.id)
    }.to raise_error(ActiveRecord::RecordInvalid)
    Imports::ProcessJob.clear

    import.reload
    expect(import.status).to eq("failed")
    expect(import.error_summary).to be_present
    expect(import.imported_transactions.count).to eq(0)
  end

  it "allows active members to inspect imports and denies cross-team import access" do
    create_import(key: "visible")
    id = import_id
    perform_import_jobs(id.to_i)

    get "/teams/#{@team.id}/imports", headers: headers_for(@viewer)
    expect(response).to have_http_status(:ok)
    get "/teams/#{@team.id}/imports/#{id}", headers: headers_for(@viewer)
    expect(response).to have_http_status(:ok)

    other_user = create_user("outside-import-team@example.com")
    other_team, = Teams::Create.call(user: other_user, attributes: { name: "Outside", slug: "outside-import-#{SecureRandom.hex(4)}" })
    get "/teams/#{other_team.id}/imports/#{id}", headers: headers_for(@requester)
    expect(response).to have_http_status(:not_found)
  end

  it "allows admin acceptance and creates one audited expense attributed to the requester" do
    create_import(key: "accept-admin")
    perform_import_jobs(import_id.to_i)
    transaction = ImportedTransaction.find_by!(import_id: import_id)

    expect {
      post imported_transaction_path(import_id, transaction.id, :accept), headers: headers_for(@admin), as: :json
    }.to change(Expense, :count).by(1).and change(AuditLog, :count).by(2)

    expect(response).to have_http_status(:ok)
    expect(transaction.reload).to have_attributes(status: "accepted", reviewed_by_membership_id: @admin_membership.id)
    expense = transaction.reload.expense
    expect(expense).to have_attributes(
      creator_membership_id: @requester_membership.id,
      member_membership_id: @requester_membership.id,
      imported_transaction_id: transaction.id,
      amount: BigDecimal("72.35"),
      currency: "USD",
      merchant: "Railway",
      description: "Regional fare",
      category: "Travel",
      incurred_on: Date.current,
      status: "draft"
    )
    expect(expense.audit_logs.find_by!(category: "workflow", event_type: "import_accepted").change_data).to include(
      "before" => { "imported_transaction_status" => "pending" },
      "after" => include("imported_transaction_status" => "accepted", "reviewer_membership_id" => @admin_membership.id)
    )
  end

  it "allows an approver to accept and rejects a creator or viewer" do
    create_import(key: "accept-approver")
    perform_import_jobs(import_id.to_i)
    transaction = ImportedTransaction.find_by!(import_id: import_id)

    post imported_transaction_path(import_id, transaction.id, :accept), headers: headers_for(@requester), as: :json
    expect(response).to have_http_status(:forbidden)
    post imported_transaction_path(import_id, transaction.id, :reject),
      params: { imported_transaction: { rejection_reason: "Unauthorized" } },
      headers: headers_for(@requester), as: :json
    expect(response).to have_http_status(:forbidden)

    post imported_transaction_path(import_id, transaction.id, :accept), headers: headers_for(@viewer), as: :json
    expect(response).to have_http_status(:forbidden)
    post imported_transaction_path(import_id, transaction.id, :reject),
      params: { imported_transaction: { rejection_reason: "Unauthorized" } },
      headers: headers_for(@viewer), as: :json
    expect(response).to have_http_status(:forbidden)

    post imported_transaction_path(import_id, transaction.id, :accept), headers: headers_for(@approver), as: :json
    expect(response).to have_http_status(:ok)
    expect(transaction.reload.reviewed_by_membership_id).to eq(@approver_membership.id)
    expect(transaction.expense.creator_membership_id).to eq(@requester_membership.id)
  end

  it "rejects a pending transaction without an audit row and requires a reason" do
    create_import(key: "reject")
    perform_import_jobs(import_id.to_i)
    transaction = ImportedTransaction.find_by!(import_id: import_id)
    audits_before = AuditLog.count

    post imported_transaction_path(import_id, transaction.id, :reject), headers: headers_for(@approver), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(transaction.reload.status).to eq("pending")

    post imported_transaction_path(import_id, transaction.id, :reject),
      params: { imported_transaction: { rejection_reason: "Not a team expense" } },
      headers: headers_for(@approver), as: :json

    expect(response).to have_http_status(:ok)
    expect(transaction.reload).to have_attributes(
      status: "rejected",
      reviewed_by_membership_id: @approver_membership.id,
      rejection_reason: "Not a team expense"
    )
    expect(transaction.reviewed_at).to be_present
    expect(transaction.expense).to be_nil
    expect(AuditLog.count).to eq(audits_before)
  end

  it "returns 409 for repeated acceptance/rejection and 404 for cross-team transaction access" do
    create_import(key: "repeat-accept")
    perform_import_jobs(import_id.to_i)
    transaction = ImportedTransaction.find_by!(import_id: import_id)
    post imported_transaction_path(import_id, transaction.id, :accept), headers: headers_for(@admin), as: :json
    expect(response).to have_http_status(:ok)
    expect { post imported_transaction_path(import_id, transaction.id, :accept), headers: headers_for(@admin), as: :json }.not_to change(Expense, :count)
    expect(response).to have_http_status(:conflict)

    create_import(key: "repeat-reject", transactions: [@payload.merge(external_transaction_id: "reject-repeat-id")])
    rejected_import_id = import_id
    perform_import_jobs(rejected_import_id.to_i)
    rejected = ImportedTransaction.find_by!(import_id: rejected_import_id)
    post imported_transaction_path(rejected_import_id, rejected.id, :reject), params: { imported_transaction: { rejection_reason: "No" } }, headers: headers_for(@admin), as: :json
    expect(response).to have_http_status(:ok)
    post imported_transaction_path(rejected_import_id, rejected.id, :reject), params: { imported_transaction: { rejection_reason: "Again" } }, headers: headers_for(@admin), as: :json
    expect(response).to have_http_status(:conflict)

    other_user = create_user("foreign-review-owner@example.com")
    other_team, = Teams::Create.call(user: other_user, attributes: { name: "Foreign review", slug: "foreign-review-#{SecureRandom.hex(4)}" })
    get "/teams/#{other_team.id}/imports/#{rejected_import_id}/imported_transactions/#{rejected.id}", headers: headers_for(other_user)
    expect(response).to have_http_status(:not_found)
    post "/teams/#{other_team.id}/imports/#{rejected_import_id}/imported_transactions/#{rejected.id}/accept", headers: headers_for(other_user), as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "enforces database unique indexes for request and external transaction keys" do
    Import.create!(team: @team, requested_by_membership: @requester_membership, provider: "bank", idempotency_key: "database-key")
    expect {
      Import.create!(team: @team, requested_by_membership: @requester_membership, provider: "bank", idempotency_key: "database-key")
    }.to raise_error(ActiveRecord::RecordNotUnique)

    import = Import.create!(team: @team, requested_by_membership: @requester_membership, provider: "unique-bank", idempotency_key: "external-key")
    values = {
      team: @team, import: import, provider: "unique-bank", external_account_ref: "account-unique",
      external_transaction_id: "transaction-unique", amount: 2, currency: "USD", merchant: "Shop", transaction_date: Date.current
    }
    ImportedTransaction.create!(values)
    expect { ImportedTransaction.create!(values.merge(import: import)) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "bulk accepts transactions with independent results and preserves requester mapping" do
    create_import(key: "bulk-accept", transactions: [@payload, @payload.merge(external_transaction_id: "bulk-2")])
    perform_import_jobs(import_id.to_i)
    transaction_ids = ImportedTransaction.where(import_id: import_id).order(:id).pluck(:id)

    post "/teams/#{@team.id}/imported_transactions/bulk_review",
      params: { action: "accept", ids: transaction_ids }, headers: headers_for(@admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(json.fetch("results").map { |item| item.fetch("result") }).to eq(%w[accepted accepted])
    expenses = Expense.where(imported_transaction_id: transaction_ids)
    expect(expenses.count).to eq(2)
    expect(expenses.pluck(:creator_membership_id, :member_membership_id).uniq).to eq([[@requester_membership.id, @requester_membership.id]])
  end

  it "bulk rejects with a reason and keeps rejection history on each imported transaction" do
    create_import(key: "bulk-reject", transactions: [@payload, @payload.merge(external_transaction_id: "bulk-reject-2")])
    perform_import_jobs(import_id.to_i)
    transaction_ids = ImportedTransaction.where(import_id: import_id).order(:id).pluck(:id)

    post "/teams/#{@team.id}/imported_transactions/bulk_review",
      params: { action: "reject", ids: transaction_ids, rejection_reason: "Not reimbursable" },
      headers: headers_for(@approver), as: :json

    expect(response).to have_http_status(:ok)
    expect(json.fetch("results").map { |item| item.fetch("result") }).to eq(%w[rejected rejected])
    records = ImportedTransaction.where(id: transaction_ids)
    expect(records.pluck(:status).uniq).to eq(["rejected"])
    expect(records.pluck(:reviewed_by_membership_id).uniq).to eq([@approver_membership.id])
    expect(records.pluck(:rejection_reason).uniq).to eq(["Not reimbursable"])
    expect(records.pluck(:reviewed_at).all?(&:present?)).to be(true)
  end

  it "preflights all bulk IDs and reviewer authorization before processing any item" do
    create_import(key: "bulk-preflight", transactions: [@payload])
    perform_import_jobs(import_id.to_i)
    transaction_id = ImportedTransaction.find_by!(import_id: import_id).id

    [@requester, @viewer].each do |user|
      post "/teams/#{@team.id}/imported_transactions/bulk_review",
        params: { action: "accept", ids: [transaction_id] }, headers: headers_for(user), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(ImportedTransaction.find(transaction_id).status).to eq("pending")
    end

    expect {
      post "/teams/#{@team.id}/imported_transactions/bulk_review",
        params: { action: "accept", ids: [transaction_id, -1] }, headers: headers_for(@admin), as: :json
    }.not_to change(Expense, :count)
    expect(response).to have_http_status(:not_found)
    expect(ImportedTransaction.find(transaction_id).status).to eq("pending")
  end

  it "rejects oversized bulk review payloads before processing any item" do
    oversized_ids = (1..101).to_a

    post "/teams/#{@team.id}/imported_transactions/bulk_review",
      params: { action: "accept", ids: oversized_ids }, headers: headers_for(@admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json.dig("error", "code")).to eq("invalid_ids")
  end

  it "returns an explicit per-item conflict when bulk review encounters a finalized transaction" do
    create_import(key: "bulk-finalized", transactions: [@payload, @payload.merge(external_transaction_id: "bulk-finalized-2")])
    perform_import_jobs(import_id.to_i)
    records = ImportedTransaction.where(import_id: import_id).order(:id).to_a
    ImportedTransactions::Accept.call(imported_transaction: records.first, reviewer: @admin)

    post "/teams/#{@team.id}/imported_transactions/bulk_review",
      params: { action: "accept", ids: records.map(&:id) }, headers: headers_for(@admin), as: :json

    expect(response).to have_http_status(:conflict)
    expect(json.fetch("results").map { |item| item.fetch("result") }).to eq(%w[conflict accepted])
    expect(Expense.where(imported_transaction_id: records.map(&:id)).count).to eq(2)
  end

  it "returns conflicts for a repeated bulk request without creating duplicate Expenses" do
    create_import(key: "bulk-replay", transactions: [@payload, @payload.merge(external_transaction_id: "bulk-replay-2")])
    perform_import_jobs(import_id.to_i)
    transaction_ids = ImportedTransaction.where(import_id: import_id).order(:id).pluck(:id)
    request_params = { action: "accept", ids: transaction_ids }

    post "/teams/#{@team.id}/imported_transactions/bulk_review", params: request_params, headers: headers_for(@admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(Expense.count).to eq(2)

    post "/teams/#{@team.id}/imported_transactions/bulk_review", params: request_params, headers: headers_for(@admin), as: :json
    expect(response).to have_http_status(:conflict)
    expect(json.fetch("results").map { |item| item.fetch("result") }).to eq(%w[conflict conflict])
    expect(Expense.count).to eq(2)
  end
end