use aiken/cbor
use aiken/merkle_patricia_forestry.{Leaf, Proof} as mpf
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, ScriptContext, Spend, Transaction,
  TransactionId,
}
use aiken/transaction/credential
use aiken/transaction/value
use sundae/multisig.{Signature}
use treasury/functions.{claim, verify_vesting_mint}
use treasury/types.{ClaimEntry, TreasuryDatum}

test valid_claim() {
  let treasury_output_ref =
    OutputReference {
      transaction_id: TransactionId { hash: #"00" },
      output_index: 0,
    }

  let claim_proof: Proof =
    [
      Leaf {
        skip: 0,
        key: #"5706af6ee90edf1bb85311438cfd72949f09c606209d84f28c4ff4bbd475c6f8",
        value: #"171f49ad01b2fdcf7751e1316e08415586534eb15a5bdc86a5b5e54218656feb",
      },
    ]

  let vesting_params = 1

  let sig1 = Signature { key_hash: #"a4" }

  let claim_entry =
    ClaimEntry {
      claimant: sig1,
      vesting_value: value.from_lovelace(100),
      direct_value: value.from_lovelace(100),
      vesting_parameters: cbor.serialise(vesting_params),
      vesting_program: #"00",
    }

  let treasury_owner = Signature { key_hash: "owner" }

  let datum =
    TreasuryDatum {
      owner: treasury_owner,
      treasury_root_hash: #"5bc8dea9d5aa66ed964186dbb7d26cbff832ee1c747db19c9001aecddcd21c6c",
    }

  let spend_input =
    Input {
      output_reference: treasury_output_ref,
      output: Output {
        address: credential.from_script(#"0011"),
        value: value.from_lovelace(10_000),
        datum: InlineDatum(datum),
        reference_script: None,
      },
    }

  let claimed_datum =
    TreasuryDatum {
      owner: treasury_owner,
      treasury_root_hash: #"b9306bcd5cca5033b1e7a88aabf282eeec19dd9b0f2a27ef030c085de341fa9a",
    }

  let updated_utxo =
    Output {
      address: credential.from_script(#"0011"),
      value: value.from_lovelace(10_000 - 200),
      datum: InlineDatum(claimed_datum),
      reference_script: None,
    }

  let minted_value =
    value.from_asset(#"00", #"1111", 1) |> value.to_minted_value()

  let tx =
    transaction.placeholder()
      |> fn(tx) {
          Transaction {
            ..tx,
            outputs: [updated_utxo],
            inputs: [spend_input],
            extra_signatories: [#"a4"],
            mint: minted_value,
          }
        }

  claim(
    treasury_output_ref,
    claim_proof,
    claim_entry,
    ScriptContext { purpose: Spend(treasury_output_ref), transaction: tx },
  )
}

test verify_mint_success() {
  let vesting_program = #"0000"
  let minted_value =
    value.from_asset(vesting_program, #"1111", 1) |> value.to_minted_value()

  verify_vesting_mint(vesting_program, minted_value)
}

test verify_mint_fail() fail {
  let vesting_program = #"0000"
  let minted_value =
    value.from_asset(#"0001", #"1111", 1) |> value.to_minted_value()

  verify_vesting_mint(vesting_program, minted_value)
}
