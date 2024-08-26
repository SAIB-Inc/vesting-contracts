use aiken/transaction.{ScriptContext, Spend}
use treasury/functions.{claim, withdraw}
use treasury/types.{AdminWithdraw, Claim, TreasuryDatum, TreasuryRedeemer}

validator {
  fn treasury_spend(
    datum: TreasuryDatum,
    redeemer: Data,
    context: ScriptContext,
  ) -> Bool {
    expect typed_redeemer: TreasuryRedeemer = redeemer
    when context.purpose is {
      Spend(output_reference) ->
        when typed_redeemer is {
          Claim(claim_proof, claim_entry) ->
            claim(output_reference, claim_proof, claim_entry, context)
          AdminWithdraw -> withdraw(datum, context)
        }
      _ -> False
    }
  }
}
