use aiken/bytearray.{concat}
use aiken/cbor.{serialise}
use aiken/hash.{blake2b_256}
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, ScriptContext,
  Transaction, TransactionId, WithdrawFrom,
}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{add}
use linear_vesting/functions.{
  claim, get_unique_ident_from_inputs, get_vest_position_ident, mint_and_burn,
} as linear_vesting_functions
use linear_vesting/types.{LinearVestingParameters}
use utils/functions.{ident_to_asset_name} as utils_functions
use utils/types.{LinearVestingPosition, ReferenceNft, UserNft} as utils_types

test vesting_claim_zero_withdraw() {
  let valdiator_hash = #"0000"
  let validator_creds = ScriptCredential(valdiator_hash)
  let input_datum1 =
    LinearVestingParameters {
      start_time: 6,
      vest_frequency: 1,
      vest_periods: 3,
      cliff_time: 0,
    }
  let input_datum2 =
    LinearVestingParameters {
      start_time: 7,
      vest_frequency: 1,
      vest_periods: 3,
      cliff_time: 0,
    }

  let test_input1 =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId("1234"),
        output_index: 0,
      },
      output: Output(
        Address { payment_credential: validator_creds, stake_credential: None },
        value.from_lovelace(100_000_000),
        InlineDatum(
          LinearVestingPosition {
            metadata: [],
            version: 1,
            extra: input_datum1,
          },
        ),
        None,
      ),
    }

  let test_input2 =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId("1234"),
        output_index: 1,
      },
      output: Output(
        Address { payment_credential: validator_creds, stake_credential: None },
        value.from_lovelace(100_000_001),
        InlineDatum(
          LinearVestingPosition {
            metadata: [],
            version: 1,
            extra: input_datum1,
          },
        ),
        None,
      ),
    }

  let test_input3 =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId("1236"),
        output_index: 1,
      },
      output: Output(
        Address { payment_credential: validator_creds, stake_credential: None },
        value.from_lovelace(100_000_002),
        InlineDatum(
          LinearVestingPosition {
            metadata: [],
            version: 1,
            extra: input_datum2,
          },
        ),
        None,
      ),
    }

  let test_input4 =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId("1237"),
        output_index: 1,
      },
      output: Output(
        Address { payment_credential: validator_creds, stake_credential: None },
        value.from_lovelace(100_000_003),
        InlineDatum(
          LinearVestingPosition {
            metadata: [],
            version: 1,
            extra: input_datum2,
          },
        ),
        None,
      ),
    }

  let test_returned_output1 =
    Output(
      Address { payment_credential: validator_creds, stake_credential: None },
      value.from_lovelace(
        100_000_000 + 100_000_001 - ( 100_000_000 + 100_000_001 ) / 3 * 2,
      ),
      InlineDatum(
        LinearVestingPosition {
          metadata: [],
          version: 1,
          extra: LinearVestingParameters {
            start_time: 8,
            vest_frequency: 1,
            vest_periods: 1,
            cliff_time: 0,
          },
        },
      ),
      None,
    )

  let test_returned_output2 =
    Output(
      Address { payment_credential: validator_creds, stake_credential: None },
      value.from_lovelace(
        100_000_002 + 100_000_003 - ( 100_000_002 + 100_000_003 ) / 3 * 1,
      ),
      InlineDatum(
        LinearVestingPosition {
          metadata: [],
          version: 1,
          extra: LinearVestingParameters {
            start_time: 8,
            vest_frequency: 1,
            vest_periods: 2,
            cliff_time: 0,
          },
        },
      ),
      None,
    )

  let minted_value =
    value.zero()
      |> add(
          valdiator_hash,
          ident_to_asset_name(
            blake2b_256(
              concat(
                serialise(test_input1.output_reference),
                serialise(test_input2.output_reference),
              ),
            ),
            ReferenceNft,
          ),
          1,
        )
      |> add(
          valdiator_hash,
          ident_to_asset_name(
            blake2b_256(
              concat(
                serialise(test_input3.output_reference),
                serialise(test_input4.output_reference),
              ),
            ),
            ReferenceNft,
          ),
          1,
        )

  let test_returned_output1 =
    test_returned_output1
      |> fn(output) {
          Output {
            ..output,
            value: output.value
              |> add(
                  valdiator_hash,
                  ident_to_asset_name(
                    blake2b_256(
                      concat(
                        serialise(test_input1.output_reference),
                        serialise(test_input2.output_reference),
                      ),
                    ),
                    ReferenceNft,
                  ),
                  1,
                ),
          }
        }

  let test_returned_output2 =
    test_returned_output2
      |> fn(output) {
          Output {
            ..output,
            value: output.value
              |> add(
                  valdiator_hash,
                  ident_to_asset_name(
                    blake2b_256(
                      concat(
                        serialise(test_input3.output_reference),
                        serialise(test_input4.output_reference),
                      ),
                    ),
                    ReferenceNft,
                  ),
                  1,
                ),
          }
        }

  let context =
    ScriptContext {
      purpose: WithdrawFrom(Inline(validator_creds)),
      transaction: transaction.placeholder()
        |> fn(transaction) {
            Transaction {
              ..transaction,
              withdrawals: [Pair(Inline(validator_creds), 0)],
              inputs: [test_input1, test_input2, test_input3, test_input4],
              outputs: [test_returned_output1, test_returned_output2],
              mint: minted_value |> value.to_minted_value(),
              validity_range: Interval {
                lower_bound: IntervalBound {
                  bound_type: Finite(8),
                  is_inclusive: True,
                },
                upper_bound: IntervalBound {
                  bound_type: Finite(10),
                  is_inclusive: True,
                },
              },
            }
          },
    }
  claim(valdiator_hash, context)
}

test treasury_deposit_mint() {
  let validator_hash = #"0000"

  let input1 =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId("1234"),
        output_index: 0,
      },
      output: Output(
        Address {
          payment_credential: ScriptCredential(validator_hash),
          stake_credential: None,
        },
        value.from_lovelace(100_000_000),
        InlineDatum(
          LinearVestingParameters {
            start_time: 6,
            vest_frequency: 1,
            vest_periods: 3,
            cliff_time: 0,
          },
        ),
        None,
      ),
    }

  let input2 =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId("1235"),
        output_index: 0,
      },
      output: Output(
        Address {
          payment_credential: ScriptCredential(validator_hash),
          stake_credential: None,
        },
        value.from_lovelace(100_000_000),
        InlineDatum(
          LinearVestingParameters {
            start_time: 6,
            vest_frequency: 1,
            vest_periods: 3,
            cliff_time: 0,
          },
        ),
        None,
      ),
    }

  let input3 =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId("1235"),
        output_index: 0,
      },
      output: Output(
        Address {
          payment_credential: ScriptCredential(validator_hash),
          stake_credential: None,
        },
        value.from_lovelace(100_000_000),
        InlineDatum(
          LinearVestingParameters {
            start_time: 6,
            vest_frequency: 1,
            vest_periods: 3,
            cliff_time: 0,
          },
        ),
        None,
      ),
    }

  let inputs =
    [input1, input2, input3]

  let ident = get_unique_ident_from_inputs(inputs)
  let output1 =
    Output(
      Address {
        payment_credential: ScriptCredential(validator_hash),
        stake_credential: None,
      },
      value.from_lovelace(300_000_000)
        |> value.add(
            validator_hash,
            get_vest_position_ident(ident, 0)
              |> ident_to_asset_name(ReferenceNft),
            1,
          ),
      InlineDatum(
        LinearVestingPosition {
          metadata: [],
          version: 1,
          extra: LinearVestingParameters {
            start_time: 6,
            vest_frequency: 1,
            vest_periods: 3,
            cliff_time: 0,
          },
        },
      ),
      None,
    )

  let output2 =
    Output(
      Address {
        payment_credential: ScriptCredential(validator_hash),
        stake_credential: None,
      },
      value.from_lovelace(300_000_000)
        |> value.add(
            validator_hash,
            get_vest_position_ident(ident, 1)
              |> ident_to_asset_name(ReferenceNft),
            1,
          ),
      InlineDatum(
        LinearVestingPosition {
          metadata: [],
          version: 1,
          extra: LinearVestingParameters {
            start_time: 6,
            vest_frequency: 1,
            vest_periods: 3,
            cliff_time: 0,
          },
        },
      ),
      None,
    )

  let output3 =
    Output(
      Address {
        payment_credential: VerificationKeyCredential(#"0000"),
        stake_credential: None,
      },
      value.from_lovelace(300_000_000)
        |> value.add(
            validator_hash,
            get_vest_position_ident(ident, 0)
              |> ident_to_asset_name(UserNft),
            1,
          ),
      NoDatum,
      None,
    )

  let output4 =
    Output(
      Address {
        payment_credential: VerificationKeyCredential(#"0000"),
        stake_credential: None,
      },
      value.from_lovelace(300_000_000)
        |> value.add(
            validator_hash,
            get_vest_position_ident(ident, 1)
              |> ident_to_asset_name(UserNft),
            1,
          ),
      NoDatum,
      None,
    )

  let context =
    ScriptContext {
      purpose: Mint(validator_hash),
      transaction: transaction.placeholder()
        |> fn(transaction) {
            Transaction {
              ..transaction,
              inputs: inputs,
              outputs: [output1, output2, output3, output4],
              mint: value.zero()
                |> value.add(
                    validator_hash,
                    get_vest_position_ident(ident, 0)
                      |> ident_to_asset_name(UserNft),
                    1,
                  )
                |> value.add(
                    validator_hash,
                    get_vest_position_ident(ident, 1)
                      |> ident_to_asset_name(UserNft),
                    1,
                  )
                |> value.add(
                    validator_hash,
                    get_vest_position_ident(ident, 0)
                      |> ident_to_asset_name(ReferenceNft),
                    1,
                  )
                |> value.add(
                    validator_hash,
                    get_vest_position_ident(ident, 1)
                      |> ident_to_asset_name(ReferenceNft),
                    1,
                  )
                |> value.to_minted_value(),
            }
          },
    }
  mint_and_burn(validator_hash, context)
}
