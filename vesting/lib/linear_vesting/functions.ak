use aiken/bytearray.{concat}
use aiken/cbor.{diagnostic, serialise}
use aiken/dict.{Dict}
use aiken/hash.{blake2b_256}
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{Datum, InlineDatum, Input, Output, ScriptContext}
use aiken/transaction/value.{AssetName, PolicyId, Value, merge}
use linear_vesting/types.{LinearVestingParameters} as linear_vesting_types
use utils/functions.{find_script_inputs, ident_to_asset_name}
use utils/types.{LinearVestingPosition, ReferenceNft} as utils_types

pub fn claim(validator_hash: ByteArray, context: ScriptContext) {
  // Get all inputs being unlocked from the vesting script
  let script_inputs =
    find_script_inputs(context.transaction.inputs, validator_hash)

  // Get all outputs to be sent to the vesting script
  let script_outputs =
    context.transaction.outputs
      |> transaction.find_script_outputs(validator_hash)

  // Group Inputs by Vesting Parameters
  let resolved_inputs_by_params =
    group_outputs_by_vesting_datum(
      script_inputs |> list.map(fn(input) { input.output }),
    )

  // Group Outputs by Vesting Parameters
  let outputs_by_params = group_outputs_by_vesting_datum(script_outputs)

  let expected_output_values_by_params =
    calculate_returnable_values_by_params(resolved_inputs_by_params, context)

  trace @"Expected returnable values"
  trace diagnostic(expected_output_values_by_params)

  let total_outputs_values_by_params =
    outputs_by_params |> outputs_by_params_to_values_by_params(validator_hash)

  trace @"Total output values"
  trace diagnostic(total_outputs_values_by_params)

  // Check Values and Datum is correct based on the vesting parameters
  // @@@ TODO: this will not match the value of `expected_output_values_by_params` because it does not
  // take into account the reference NFTs attached to the vesting output, should adjust the logic of
  // `outputs_by_params_to_values_by_params()` to ignore reference NFTs
  let is_output_values_correct =
    expected_output_values_by_params == total_outputs_values_by_params

  let is_mint_valid = mint_and_burn(validator_hash, context)

  and {
    is_output_values_correct?,
    is_mint_valid?,
  }
}

// @TODO: Check name and image of NFT
// both name and image are validator parameters
// _dsadasdas
// check metadata dictionary count must be 2
pub fn try_extract_vesting_datum(
  on_chain_datum: Datum,
) -> Option<LinearVestingParameters> {
  expect InlineDatum(inline_datum) = on_chain_datum
  expect cip68_position: LinearVestingPosition = inline_datum
  Some(cip68_position.extra)
}

pub fn sum_values(values: List<Value>) -> Value {
  values |> list.foldl(value.zero(), fn(a, b) { a |> merge(b) })
}

pub fn calculate_returnable_values_by_params(
  outputs_by_params: Dict<
    ByteArray,
    Pair<LinearVestingParameters, List<Output>>,
  >,
  context: ScriptContext,
) -> Dict<ByteArray, Value> {
  let returnable_params_and_values =
    outputs_by_params
      |> dict.map(
          fn(_k, v) {
            let Pair(params, outputs) = v
            let total_value =
              sum_values(outputs |> list.map(fn(output) { output.value }))

            // Extract Parameters
            let periods_remaining = params.vest_periods

            // Get Current Time
            expect Finite(current_time_lower) =
              context.transaction.validity_range.lower_bound.bound_type

            // Determine the number of vesting periods that have passed
            let periods_passed =
              ( current_time_lower - params.start_time ) / params.vest_frequency

            if periods_passed >= periods_remaining {
              // Check if the user can just claim everything
              None
            } else if params.cliff_time > current_time_lower {
              // Check if the user is still in the cliff period then no assets can be claimed yet
              Some(Pair(params, total_value))
            } else {
              // Find Vested / Locked Assets
              let vested_assets = total_value |> value.flatten()

              let divide_fn =
                divide_amount_by_periods(_, periods_passed, periods_remaining)

              let assets_to_release =
                vested_assets
                  |> list.map(divide_fn)

              // Calculate the Correct Value in the Output
              let correct_returned_value_in_output =
                list.foldl(
                  assets_to_release,
                  total_value,
                  fn(acc, asset) {
                    let (policy_id, asset_name, amount) = acc
                    asset |> value.add(policy_id, asset_name, -amount)
                  },
                )

              // Calculate Correct Updated Vesting Parameters Datum
              let correct_vesting_params =
                calculate_returnable_params(params, context)

              Some(
                Pair(correct_vesting_params, correct_returned_value_in_output),
              )
            }
          },
        )

  let final =
    returnable_params_and_values
      |> dict.foldl(
          dict.new(),
          fn(_k, v, new_dict) {
            when v is {
              Some(Pair(params, value)) ->
                new_dict |> dict.insert(serialise(params), value)
              None -> new_dict
            }
          },
        )
  final
}

pub fn mint_and_burn(policy_id: PolicyId, context: ScriptContext) -> Bool {
  let tx_inputs = context.transaction.inputs
  let tx_outputs = context.transaction.outputs
  let tx_identifier = get_unique_ident_from_inputs(tx_inputs)

  // @@@@ Possible fail due to previously minted vesting NFTs being included as input
  // @TODO: Either filter reference nfts that's owned by the validator
  // or filter by only reference NFTs to ensure only inputs from validator are evaluated
  let resolved_script_inputs =
    context.transaction.inputs
      |> list.foldl([], fn(input, acc) { acc |> list.push(input.output) })
      |> transaction.find_script_outputs(policy_id)

  let reference_nfts_to_burn =
    resolved_script_inputs
      |> list.flat_map(
          fn(input) {
            input.value
              |> value.flatten_with(
                  fn(c_policy_id, asset_name, amount) {
                    if c_policy_id == policy_id {
                      Some((policy_id, asset_name, amount))
                    } else {
                      None
                    }
                  },
                )
          },
        )

  // Find all outputs sent to the vesting script
  let script_outputs =
    tx_outputs
      |> transaction.find_script_outputs(policy_id)

  // Put index on outputs
  let outputs_with_index =
    script_outputs
      |> list.indexed_map(fn(index, output) { Pair(index, output) })

  let vesting_outputs =
    outputs_with_index
      |> list.map(
          fn(output_with_index) {
            let Pair(index, output) = output_with_index

            // Just to make sure the datum is correct
            expect Some(linear_params) = try_extract_vesting_datum(output.datum)

            let position_ident = get_vest_position_ident(tx_identifier, index)
            let position_nft_name =
              ident_to_asset_name(position_ident, ReferenceNft)

            let has_nft =
              (
                output.value
                  |> value.quantity_of(policy_id, position_nft_name)
              ) == 1

            when has_nft is {
              True -> Some((position_ident, linear_params))
              False -> None
            }
          },
        )

  let vesting_outputs_count = vesting_outputs |> list.length()

  let has_vesting_outputs = vesting_outputs_count > 0

  let is_positions_correct =
    vesting_outputs
      |> list.all(
          fn(elem) {
            expect Some((position_ident, _)) = elem
            outputs_contains_nft(
              tx_outputs,
              policy_id,
              ident_to_asset_name(position_ident, ReferenceNft),
            )
          },
        )

  let flattened_mint =
    context.transaction.mint
      |> value.from_minted_value()
      |> value.flatten()

  let is_positions_minted =
    (
      flattened_mint
        |> list.length()
    ) >= vesting_outputs_count

  // @TODO: Ensure UserNfts are burned together with ref NFTs
  // make sure there's a cip68 metadata
  let is_positions_burned =
    reference_nfts_to_burn
      |> list.all(
          fn(x) {
            let (x_policy_id, x_asset_name, x_amount) = x
            flattened_mint
              |> list.any(
                  fn(y) {
                    let (y_policy_id, y_asset_name, y_amount) = y
                    x_policy_id == y_policy_id && x_asset_name == y_asset_name && -x_amount == y_amount
                  },
                )
          },
        )

  and {
    has_vesting_outputs?,
    is_positions_correct?,
    is_positions_minted?,
    is_positions_burned?,
  }
}

pub fn outputs_contains_nft(
  outputs: List<Output>,
  policy_id: PolicyId,
  nft_name: AssetName,
) -> Bool {
  outputs
    |> list.any(
        fn(output) {
          (
            output.value
              |> value.quantity_of(policy_id, nft_name)
          ) == 1
        },
      )
}

pub fn get_vest_position_ident(base_ident: ByteArray, index: Int) -> ByteArray {
  blake2b_256(concat(base_ident, serialise(index)))
}

pub fn get_unique_ident_from_inputs(inputs: List<Input>) -> ByteArray {
  inputs
    |> list.foldl(
        #"",
        fn(input, acc) {
          blake2b_256(concat(acc, serialise(input.output_reference)))
        },
      )
}

pub fn calculate_returnable_params(
  params: LinearVestingParameters,
  context: ScriptContext,
) -> LinearVestingParameters {
  // Get Current Time
  expect Finite(current_time_lower) =
    context.transaction.validity_range.lower_bound.bound_type

  // Determine the number of vesting periods that have passed
  let periods_passed =
    ( current_time_lower - params.start_time ) / params.vest_frequency

  let correct_vesting_params =
    LinearVestingParameters {
      start_time: params.start_time + periods_passed * params.vest_frequency,
      vest_periods: params.vest_periods - periods_passed,
      vest_frequency: params.vest_frequency,
      cliff_time: params.cliff_time,
    }

  correct_vesting_params
}

pub fn outputs_by_params_to_values_by_params(
  outputs_by_params: Dict<
    ByteArray,
    Pair<LinearVestingParameters, List<Output>>,
  >,
  vesting_program: ByteArray,
) -> Dict<ByteArray, Value> {
  outputs_by_params
    |> dict.map(
        fn(_k, outputs_with_params) {
          let Pair(_, outputs) = outputs_with_params
          sum_values(
            outputs
              |> list.map(
                  fn(resolved_input) {
                    resolved_input.value
                      |> value.flatten()
                      |> list.filter(
                          fn(a) {
                            let (policy_id, _, _) = a
                            policy_id != vesting_program
                          },
                        )
                      |> list.foldl(
                          value.zero(),
                          fn(val, acc) {
                            let (policy_id, asset_name, quantity) = val
                            acc
                              |> value.merge(
                                  value.from_asset(
                                    policy_id,
                                    asset_name,
                                    quantity,
                                  ),
                                )
                          },
                        )
                  },
                ),
          )
        },
      )
}

// @TODO: need to change LinearVestingParameters to LinearVestingPosition
pub fn group_outputs_by_vesting_datum(
  validator_outputs: List<Output>,
) -> Dict<ByteArray, Pair<LinearVestingParameters, List<Output>>> {
  validator_outputs
    |> list.foldl(
        dict.new(),
        fn(output, acc) {
          expect Some(linear_params) = try_extract_vesting_datum(output.datum)
          let vesting_datum_bytes = serialise(linear_params)
          acc
            |> dict.insert_with(
                vesting_datum_bytes,
                Pair(linear_params, [output]),
                fn(_k, a, b) {
                  let Pair(params_a, outputs_a) = a
                  let Pair(_, outputs_b) = b
                  Some(Pair(params_a, outputs_a |> list.concat(outputs_b)))
                },
              )
        },
      )
}

pub fn divide_amount_by_periods(
  asset: (PolicyId, AssetName, Int),
  periods_passed: Int,
  periods: Int,
) {
  (asset.1st, asset.2nd, asset.3rd * periods_passed / periods)
}
