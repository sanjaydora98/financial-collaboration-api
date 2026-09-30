module Reimbursements
  class PaymentSimulator
    Result = Struct.new(:status, :failure_reason, keyword_init: true)

    def self.call(reimbursement:)
      Result.new(status: "paid")
    end
  end
end