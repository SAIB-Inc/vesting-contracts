use aiken/cbor
use aiken/dict
use aiken/merkle_patricia_forestry.{MerklePatriciaForestry, Proof} as mpf
use aiken/transaction.{
  Datum, InlineDatum, Input, Output, OutputReference, ScriptContext, Transaction,
  find_input, find_script_outputs,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{MintedValue, Value, merge, negate}
use sundae/multisig.{satisfied}
use treasury/types.{ClaimEntry, TreasuryDatum}

pub fn claim(
  treasury_output_reference: OutputReference,
  claim_proof: Proof,
  claim_entry: ClaimEntry,
  context: ScriptContext,
) -> Bool {
  let tx = context.transaction

  expect Some(Input(_, treasury_input)) =
    find_input(tx.inputs, treasury_output_reference)

  expect Address(ScriptCredential(treasury_script_hash), _) =
    treasury_input.address

  expect [treasury_output] =
    find_script_outputs(tx.outputs, treasury_script_hash)

  let current_treasury_datum = extract_treasury_datum(treasury_input.datum)

  let updated_root_hash =
    calculate_claimed_trie(
      claim_entry,
      current_treasury_datum.treasury_root_hash,
      claim_proof,
    )
      |> mpf.root()

  let updated_treasury_datum =
    TreasuryDatum {
      ..current_treasury_datum,
      treasury_root_hash: updated_root_hash,
    }

  let spent_treasury_datum = extract_treasury_datum(treasury_output.datum)

  and {
    treasury_input.address == treasury_output.address,
    verify_claim_value(claim_entry, treasury_input.value, treasury_output.value),
    verify_claim_datum(
      updated_treasury_datum,
      spent_treasury_datum,
      updated_root_hash,
    ),
    verify_vesting_mint(claim_entry.vesting_program, tx.mint),
    satisfied(
      claim_entry.claimant,
      tx.extra_signatories,
      tx.validity_range,
      tx.withdrawals,
    ),
  }
}

pub fn extract_treasury_datum(on_chain_datum: Datum) -> TreasuryDatum {
  expect InlineDatum(inline_datum) = on_chain_datum
  expect casted_datum: TreasuryDatum = inline_datum
  casted_datum
}

pub fn calculate_claimed_trie(
  claim_entry: ClaimEntry,
  root_hash: ByteArray,
  proof: Proof,
) -> MerklePatriciaForestry {
  let updated_claim_entry =
    ClaimEntry {
      ..claim_entry,
      direct_value: value.zero(),
      vesting_value: value.zero(),
    }

  mpf.from_root(root_hash)
    |> mpf.update(
        cbor.serialise(claim_entry.claimant),
        proof,
        cbor.serialise(claim_entry),
        cbor.serialise(updated_claim_entry),
      )
}

pub fn verify_vesting_mint(vesting_hash: ByteArray, mint: MintedValue) -> Bool {
  let minted_value = mint |> value.from_minted_value()
  let vesting_mints = minted_value |> value.tokens(vesting_hash)
  dict.size(vesting_mints) > 0
}

pub fn verify_claim_datum(
  input_datum: TreasuryDatum,
  output_datum: TreasuryDatum,
  updated_trie_hash: ByteArray,
) -> Bool {
  output_datum == TreasuryDatum {
    ..input_datum,
    treasury_root_hash: updated_trie_hash,
  }
}

pub fn verify_claim_value(
  claim_entry: ClaimEntry,
  input_value: Value,
  output_value: Value,
) -> Bool {
  let claimed_value =
    claim_entry.vesting_value |> merge(claim_entry.direct_value) |> negate()
  let expected_output_value = input_value |> merge(claimed_value)
  expected_output_value == output_value
}

pub fn verify_claim(
  claim_proof: Proof,
  claim_entry: ClaimEntry,
  root: ByteArray,
) -> Bool {
  mpf.from_root(root)
    |> mpf.has(
        cbor.serialise(claim_entry.claimant),
        cbor.serialise(claim_entry),
        claim_proof,
      )
}
