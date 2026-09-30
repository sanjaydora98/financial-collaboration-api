require "rails_helper"

RSpec.describe "Import concurrency" do
  self.use_transactional_tests = false

  before do
    @requester = create_user("import-race-requester-#{SecureRandom.hex(4)}@example.com")
    @team, @requester_membership = Teams::Create.call(
      user: @requester,
      attributes: { name: "Import race", slug: "import-race-#{SecureRandom.hex(4)}" }
    )
    @reviewer = create_user("import-race-reviewer-#{SecureRandom.hex(4)}@example.com")
    @reviewer_membership = TeamMembership.create!(team: @team, user: @reviewer, role: "admin")
    @payload = {
      external_account_ref: "race-account",
      external_transaction_id: "race-transaction-#{SecureRandom.hex(4)}",
      amount: 18.75,
      currency: "USD",
      merchant: "Race merchant",
      description: "Concurrent transaction",
      category: "Travel",
      transaction_date: Date.current
    }
  end

  after do
    AuditLog.where(team_id: @team.id).delete_all
    Expense.where(team_id: @team.id).delete_all
    ImportedTransaction.where(team_id: @team.id).delete_all
    Import.where(team_id: @team.id).delete_all
    TeamMembership.where(team_id: @team.id).delete_all
    Team.where(id: @team.id).delete_all
    User.where(id: [@requester.id, @reviewer.id]).delete_all
  end

  it "deduplicates a transaction processed simultaneously by two different imports" do
    imports = 2.times.map do |index|
      Import.create!(
        team: @team,
        requested_by_membership: @requester_membership,
        provider: "bank",
        idempotency_key: "race-import-#{index}-#{SecureRandom.hex(4)}",
        status: "queued"
      )
    end

    results = run_concurrently(imports) do |import|
      Imports::Process.call(import: Import.find(import.id), transactions: [@payload])
      :success
    end

    expect(results).to eq(%i[success success])
    expect(ImportedTransaction.where(team: @team, provider: "bank", external_account_ref: "race-account",
      external_transaction_id: @payload[:external_transaction_id]).count).to eq(1)
    expect(imports.map { |record| record.reload.status }).to eq(%w[completed completed])
  end

  it "serializes two workers processing the same Import ID" do
    import = Import.create!(
      team: @team,
      requested_by_membership: @requester_membership,
      provider: "bank",
      idempotency_key: "same-import-race-#{SecureRandom.hex(4)}",
      status: "queued"
    )

    results = run_concurrently([import, import]) do |record|
      Imports::Process.call(import: Import.find(record.id), transactions: [@payload])
      :completed
    end

    expect(results).to eq(%i[completed completed])
    expect(import.reload.status).to eq("completed")
    expect(import.imported_transactions.count).to eq(1)
  end

  it "allows only one concurrent acceptance and creates one Expense" do
    import = Import.create!(team: @team, requested_by_membership: @requester_membership,
      provider: "bank", idempotency_key: "accept-race-#{SecureRandom.hex(4)}", status: "completed")
    imported_transaction = ImportedTransaction.create!(@payload.merge(team: @team, import: import, provider: "bank"))

    results = run_concurrently([imported_transaction, imported_transaction]) do |record|
      ImportedTransactions::Accept.call(imported_transaction: ImportedTransaction.find(record.id), reviewer: User.find(@reviewer.id))
      :success
    rescue ImportedTransactions::ReviewConflict
      :conflict
    end

    expect(results.count(:success)).to eq(1)
    expect(results.count(:conflict)).to eq(1)
    expect(imported_transaction.reload).to have_attributes(status: "accepted", reviewed_by_membership_id: @reviewer_membership.id)
    expect(imported_transaction.expense).to be_present
    expect(Expense.where(imported_transaction_id: imported_transaction.id).count).to eq(1)
  end

  it "serializes a bulk acceptance racing with a single acceptance" do
    import = Import.create!(team: @team, requested_by_membership: @requester_membership,
      provider: "bank", idempotency_key: "bulk-race-#{SecureRandom.hex(4)}", status: "completed")
    imported_transaction = ImportedTransaction.create!(@payload.merge(team: @team, import: import, provider: "bank"))

    outcomes = run_concurrently([:bulk, :single]) do |kind|
      transaction = ImportedTransaction.find(imported_transaction.id)
      reviewer = User.find(@reviewer.id)
      if kind == :bulk
        result = ImportedTransactions::BulkReview.call(transactions: [transaction], reviewer: reviewer, action: "accept")
        result.outcomes.first.fetch(:result).to_sym
      else
        ImportedTransactions::Accept.call(imported_transaction: transaction, reviewer: reviewer)
        :accepted
      end
    rescue ImportedTransactions::ReviewConflict
      :conflict
    end

    expect(outcomes.count(:accepted)).to eq(1)
    expect(outcomes.count(:conflict)).to eq(1)
    expect(imported_transaction.reload.status).to eq("accepted")
    expect(Expense.where(imported_transaction_id: imported_transaction.id).count).to eq(1)
  end

  private

  def create_user(email)
    User.create!(email: email, name: email.split("@").first, password: "password123")
  end

  def run_concurrently(arguments, &operation)
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = arguments.map do |argument|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            results << operation.call(argument)
          rescue StandardError => error
            results << error
          end
        end
      end
    end

    arguments.length.times { ready.pop }
    arguments.length.times { start << true }
    threads.each(&:join)
    arguments.length.times.map { results.pop }
  end
end