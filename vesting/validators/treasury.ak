use aiken/transaction.{ScriptContext, Spend}
use treasury/functions.{claim}
use treasury/types.{AdminWithdraw, Claim, TreasuryDatum, TreasuryRedeemer}

validator {
  fn treasury_spend(
    _datum: TreasuryDatum,
    redeemer: TreasuryRedeemer,
    context: ScriptContext,
  ) -> Bool {
    when context.purpose is {
      Spend(output_reference) ->
        when redeemer is {
          Claim(claim_proof, claim_entry) ->
            claim(output_reference, claim_proof, claim_entry, context)
          AdminWithdraw -> True
        }
      _ -> False
    }
  }
}
