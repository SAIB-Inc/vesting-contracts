use aiken/bytearray
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/string
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
use utils/types.{
  LinearVestingPosition, ReferenceNft, UserNft, reference_prefix,
  user_nft_prefix, vesting_nft_image, vesting_nft_prefix,
} as utils_types

test vesting_claim_zero_withdraw() {
  let validator_hash = #"0000"
  let validator_creds = ScriptCredential(validator_hash)
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
        value.from_lovelace(100_000_000)
          |> value.add(
              validator_hash,
              reference_prefix |> bytearray.concat(#"1111"),
              1,
            ),
        InlineDatum(
          LinearVestingPosition {
            metadata: [
              (
                bytearray.from_string(@"name"),
                bytearray.from_string(
                  string.concat(vesting_nft_prefix, @"test1"),
                ),
              ),
              (
                bytearray.from_string(@"image"),
                bytearray.from_string(vesting_nft_image),
              ),
            ],
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
        value.from_lovelace(100_000_001)
          |> value.add(
              validator_hash,
              reference_prefix |> bytearray.concat(#"2111"),
              1,
            ),
        InlineDatum(
          LinearVestingPosition {
            metadata: [
              (
                bytearray.from_string(@"name"),
                bytearray.from_string(
                  string.concat(vesting_nft_prefix, @"test2"),
                ),
              ),
              (
                bytearray.from_string(@"image"),
                bytearray.from_string(vesting_nft_image),
              ),
            ],
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
        value.from_lovelace(100_000_002)
          |> value.add(
              validator_hash,
              reference_prefix |> bytearray.concat(#"3111"),
              1,
            ),
        InlineDatum(
          LinearVestingPosition {
            metadata: [
              (
                bytearray.from_string(@"name"),
                bytearray.from_string(
                  string.concat(vesting_nft_prefix, @"test3"),
                ),
              ),
              (
                bytearray.from_string(@"image"),
                bytearray.from_string(vesting_nft_image),
              ),
            ],
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
        value.from_lovelace(100_000_003)
          |> value.add(
              validator_hash,
              reference_prefix |> bytearray.concat(#"4111"),
              1,
            ),
        InlineDatum(
          LinearVestingPosition {
            metadata: [
              (
                bytearray.from_string(@"name"),
                bytearray.from_string(
                  string.concat(vesting_nft_prefix, @"test4"),
                ),
              ),
              (
                bytearray.from_string(@"image"),
                bytearray.from_string(vesting_nft_image),
              ),
            ],
            version: 1,
            extra: input_datum2,
          },
        ),
        None,
      ),
    }

  let inputs =
    [test_input1, test_input2, test_input3, test_input4]

  let ident = get_unique_ident_from_inputs(inputs)

  let test_returned_output1 =
    Output(
      Address { payment_credential: validator_creds, stake_credential: None },
      value.from_lovelace(
        100_000_000 + 100_000_001 - ( 100_000_000 + 100_000_001 ) / 3 * 2,
      ),
      InlineDatum(
        LinearVestingPosition {
          metadata: [
            (
              bytearray.from_string(@"name"),
              bytearray.from_string(string.concat(vesting_nft_prefix, @"test1")),
            ),
            (
              bytearray.from_string(@"image"),
              bytearray.from_string(vesting_nft_image),
            ),
          ],
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
          metadata: [
            (
              bytearray.from_string(@"name"),
              bytearray.from_string(string.concat(vesting_nft_prefix, @"test2")),
            ),
            (
              bytearray.from_string(@"image"),
              bytearray.from_string(vesting_nft_image),
            ),
          ],
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
          validator_hash,
          get_vest_position_ident(ident, 0)
            |> ident_to_asset_name(ReferenceNft),
          1,
        )
      |> add(
          validator_hash,
          get_vest_position_ident(ident, 0)
            |> ident_to_asset_name(UserNft),
          1,
        )
      |> add(
          validator_hash,
          get_vest_position_ident(ident, 1)
            |> ident_to_asset_name(ReferenceNft),
          1,
        )
      |> add(
          validator_hash,
          get_vest_position_ident(ident, 1)
            |> ident_to_asset_name(UserNft),
          1,
        )
      |> add(validator_hash, reference_prefix |> bytearray.concat(#"1111"), -1)
      |> add(validator_hash, user_nft_prefix |> bytearray.concat(#"1111"), -1)
      |> add(validator_hash, reference_prefix |> bytearray.concat(#"2111"), -1)
      |> add(validator_hash, user_nft_prefix |> bytearray.concat(#"2111"), -1)
      |> add(validator_hash, reference_prefix |> bytearray.concat(#"3111"), -1)
      |> add(validator_hash, user_nft_prefix |> bytearray.concat(#"3111"), -1)
      |> add(validator_hash, reference_prefix |> bytearray.concat(#"4111"), -1)
      |> add(validator_hash, user_nft_prefix |> bytearray.concat(#"4111"), -1)

  let test_returned_output1 =
    test_returned_output1
      |> fn(output) {
          Output {
            ..output,
            value: output.value
              |> add(
                  validator_hash,
                  get_vest_position_ident(ident, 0)
                    |> ident_to_asset_name(ReferenceNft),
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
                  validator_hash,
                  get_vest_position_ident(ident, 1)
                    |> ident_to_asset_name(ReferenceNft),
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
              inputs: inputs,
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
  claim(validator_hash, context)
}

test treasury_deposit_mint() {
  let validator_hash = #"0000"
  let treasury_validator_hash = #"0001"

  let input1 =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId("1234"),
        output_index: 0,
      },
      output: Output(
        Address {
          payment_credential: ScriptCredential(treasury_validator_hash),
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
          payment_credential: ScriptCredential(treasury_validator_hash),
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
          payment_credential: ScriptCredential(treasury_validator_hash),
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
          metadata: [
            (
              bytearray.from_string(@"name"),
              bytearray.from_string(string.concat(vesting_nft_prefix, @"test1")),
            ),
            (
              bytearray.from_string(@"image"),
              bytearray.from_string(vesting_nft_image),
            ),
          ],
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
          metadata: [
            (
              bytearray.from_string(@"name"),
              bytearray.from_string(string.concat(vesting_nft_prefix, @"test2")),
            ),
            (
              bytearray.from_string(@"image"),
              bytearray.from_string(vesting_nft_image),
            ),
          ],
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
        payment_credential: VerificationKeyCredential(#"000012"),
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
        payment_credential: VerificationKeyCredential(#"000012"),
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
