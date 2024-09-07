use aiken/bytearray
use aiken/cbor
use aiken/list
use aiken/merkle_patricia_forestry.{Leaf} as mpf
use aiken/transaction.{Input, NoDatum, Output, OutputReference, TransactionId}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value
use linear_vesting/functions.{get_unique_ident_from_inputs} as linear_vesting_functions
use sundae/multisig.{Signature}
use treasury/types.{AdminWithdraw, Claim, ClaimEntry, TreasuryDatum}

test print_example_datums() {
  let claim_entry_1 =
    ClaimEntry {
      claimant: Signature {
        key_hash: #"aeeca6f0668d3542b099fa5524bb517ee96bdd25a750fc65377f51d4",
      },
      vesting_value: value.from_lovelace(0),
      direct_value: value.from_lovelace(100000000),
      vesting_parameters: cbor.serialise(0),
      vesting_program: #"00",
    }
  let claim_entry_2 =
    ClaimEntry {
      claimant: Signature {
        key_hash: #"e63022b0f461602484968bb10fd8f872787b862ace2d7e943292a370",
      },
      vesting_value: value.from_lovelace(0),
      direct_value: value.from_lovelace(100000000),
      vesting_parameters: cbor.serialise(0),
      vesting_program: #"00",
    }
  let claim_entry_1_spent =
    ClaimEntry { ..claim_entry_1, direct_value: value.zero() }

  trace @"claim_entry_key_1"
  trace bytearray.to_hex(cbor.serialise(claim_entry_1.claimant))
  trace @"claim_entry__value_1"
  trace bytearray.to_hex(cbor.serialise(claim_entry_1))
  trace @"claim_entry__value_1_spent"
  trace bytearray.to_hex(cbor.serialise(claim_entry_1_spent))

  trace @"claim_entry_key_2"
  trace bytearray.to_hex(cbor.serialise(claim_entry_2.claimant))
  trace @"claim_entry__value_2"
  trace bytearray.to_hex(cbor.serialise(claim_entry_2))

  let treasury_datum =
    TreasuryDatum {
      owner: Signature {
        key_hash: #"aeeca6f0668d3542b099fa5524bb517ee96bdd25a750fc65377f51d4",
      },
      treasury_root_hash: #"2325f3c999b17d4a6399bf6c02e1ff7615c13a73ecafae7fe813b9757f27ef26",
      unlock_time: 0,
    }

  trace @"treasury_datum"
  trace bytearray.to_hex(cbor.serialise(treasury_datum))

  let treasury_claimed_1_datum =
    TreasuryDatum {
      ..treasury_datum,
      treasury_root_hash: #"92ab4f0814dd27aab0fa989be6cef34ea383207957b554a332548f31d90319f5",
    }

  trace @"treasury_claimed_1_datum"
  trace bytearray.to_hex(cbor.serialise(treasury_claimed_1_datum))

  let treasury_withdraw_redeemer = AdminWithdraw

  trace @"treasury_withdraw_redeemer"
  trace bytearray.to_hex(cbor.serialise(treasury_withdraw_redeemer))

  let treasury_direct_claim_entry_1_redeemer =
    Claim {
      proof: [
        Leaf {
          skip: 0,
          key: #"f83d976e071395b7f98ba520ccdb61a1f635e58b8b361f9be5c1369cfe068799",
          value: #"eed22f0f81e87e08d932c4d9aaa6476a961cca14988b63a549c589bc9d3525e8",
        },
      ],
      entry: claim_entry_1,
    }

  trace @"treasury_direct_claim_entry_1_redeemer"
  trace bytearray.to_hex(cbor.serialise(treasury_direct_claim_entry_1_redeemer))

  let sig = Signature { key_hash: #"00" }
  trace @"Signature"
  trace bytearray.to_hex(cbor.serialise(sig))

  True
}

test print_example_asset_ident() {
  let inputs =
    [
      Input {
        output_reference: OutputReference {
          transaction_id: TransactionId {
            hash: #"3b4311db1c4a6122485d5d1aa8bffa4de304bd53f34c206ea09279675abc13ac",
          },
          output_index: 2,
        },
        output: Output {
          address: Address {
            payment_credential: VerificationKeyCredential(#"00"),
            stake_credential: None,
          },
          value: value.zero(),
          datum: NoDatum,
          reference_script: None,
        },
      },
    ]
      |> list.sort(
          fn(a, b) {
            bytearray.compare(
              cbor.serialise(a.output_reference),
              cbor.serialise(b.output_reference),
            )
          },
        )

  let ident = get_unique_ident_from_inputs(inputs)
  trace @"asset_ident"
  trace bytearray.to_hex(ident)

  True
}
