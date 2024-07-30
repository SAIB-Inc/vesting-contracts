use aiken/pairs
use aiken/transaction.{Mint, ScriptContext, WithdrawFrom}
use aiken/transaction/credential.{Inline, ScriptCredential}
use linear_vesting/functions.{claim}
use utils/functions.{get_validator_hash} as utils_functions

validator {
  fn vesting_spend(
    _datum: Data,
    _redeemer: Data,
    context: ScriptContext,
  ) -> Bool {
    // Retrieve the hash of the validator script
    let self_hash = get_validator_hash(context)

    // Check if the transaction has a withdrawal with the validator's hash as the staking credential
    // This means that the zero withdraw logic has run and validated the vesting claims
    context.transaction.withdrawals
      |> pairs.has_key(Inline(ScriptCredential(self_hash)))
  }

  fn vesting_withdraw_or_mint(_redeemer: Data, context: ScriptContext) -> Bool {
    when context.purpose is {
      Mint(_) -> True
      WithdrawFrom(Inline(ScriptCredential(validator_hash))) ->
        claim(validator_hash, context)
      _ -> False
    }
  }
}
