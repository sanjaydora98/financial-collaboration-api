module Imports
  class ProcessJob
    include Sidekiq::Job

    sidekiq_options retry: 5

    def perform(import_id, transactions)
      import = Import.find(import_id)
      Imports::Process.call(import: import, transactions: transactions)
    end
  end
end