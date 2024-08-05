use aiken/bytearray.{concat}
use aiken/cbor.{serialise}
use aiken/dict.{Dict}
use aiken/hash.{blake2b_256}
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{Datum, InlineDatum, Output, ScriptContext}
use aiken/transaction/value.{AssetName, PolicyId, Value, merge}
use linear_vesting/types.{LinearVestingParameters} as linear_vesting_types
use utils/functions.{find_script_inputs,
  get_validator_hash, ident_to_asset_name}
use utils/types.{Reference} as utils_types

pub fn claim(validator_hash: ByteArray, context: ScriptContext) {
  // Get all inputs being unlocked from the vesting script
  let script_inputs =
    find_script_inputs(context.transaction.inputs, validator_hash)
  // Group Inputs by Returnable Vesting Parameters so that we can refer to the OutputReference as the unique identifier for the NFT later
  // The inputs are merged by serialising them to thier CBOR representation, concatenating them and hashing them with blake2b_256
  let input_refs_by_returnable_params =
    script_inputs
      |> list.foldl(
          dict.new(),
          fn(input, acc) {
            let vesting_params: LinearVestingParameters =
              extract_vesting_datum(input.output.datum)
            let returnable_vesting_params =
              vesting_params |> calculate_returnable_params(context)
            acc
              |> dict.insert_with(
                  serialise(returnable_vesting_params),
                  serialise(input.output_reference),
                  fn(_k, a, b) { Some(blake2b_256(concat(a, b))) },
                )
          },
        )

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
    calculate_returnable_values_by_params(
      input_refs_by_returnable_params,
      resolved_inputs_by_params,
      context,
    )

  let total_outputs_values_by_params =
    outputs_by_params |> outputs_by_params_to_values_by_params

  // Check Values and Datum is correct based on the vesting parameters
  expected_output_values_by_params == total_outputs_values_by_params
}

pub fn extract_vesting_datum(on_chain_datum: Datum) -> LinearVestingParameters {
  expect InlineDatum(inline_datum) = on_chain_datum
  expect casted_datum: LinearVestingParameters = inline_datum
  casted_datum
}

pub fn sum_values(values: List<Value>) -> Value {
  values |> list.foldl(value.zero(), fn(a, b) { a |> merge(b) })
}

pub fn calculate_returnable_values_by_params(
  input_refs_by_returnable_params: Dict<ByteArray, ByteArray>,
  outputs_by_params: Dict<
    ByteArray,
    Pair<LinearVestingParameters, List<Output>>,
  >,
  context: ScriptContext,
) -> Dict<ByteArray, Value> {
  let validator_hash = get_validator_hash(context)
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

              expect Some(unique_nft_name) =
                input_refs_by_returnable_params
                  |> dict.get(serialise(correct_vesting_params))

              let unique_nft_name =
                ident_to_asset_name(unique_nft_name, Reference)

              let correct_returned_value_in_output =
                correct_returned_value_in_output
                  |> value.add(validator_hash, unique_nft_name, 1)
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

pub fn mint(policy_id: PolicyId, context: ScriptContext) {
  let tx_outputs = context.transaction.outputs
  let tx_identifier = get_tx_unique_ident(context)

  // Find all outputs sent to the vesting script
  let script_outputs =
    tx_outputs
      |> transaction.find_script_outputs(policy_id)

  // Put index on outputs
  let outputs_with_index =
    script_outputs
      |> list.indexed_map(fn(index, output) { Pair(index, output) })

  let outputs_with_params =
    outputs_with_index
      |> list.map(
          fn(output_with_index) {
            let Pair(index, output) = output_with_index
            let linear_params = extract_vesting_datum(output.datum)
            let position_ident = get_vest_position_ident(tx_identifier, index)
            let position_nft_name =
              ident_to_asset_name(position_ident, Reference)

            let has_nft =
              (
                output.value
                  |> value.quantity_of(policy_id, position_nft_name)
              ) == 1

            when has_nft is {
              True -> Some((index, linear_params, position_nft_name, output))
              False -> None
            }
          },
        )

  True
}

pub fn get_vest_position_ident(base_ident: ByteArray, index: Int) -> ByteArray {
  blake2b_256(concat(base_ident, serialise(index)))
}

pub fn get_tx_unique_ident(context: ScriptContext) -> ByteArray {
  let inputs = context.transaction.inputs
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
) -> Dict<ByteArray, Value> {
  outputs_by_params
    |> dict.map(
        fn(_k, outputs_with_params) {
          let Pair(_, outputs) = outputs_with_params
          sum_values(
            outputs
              |> list.map(fn(resolved_input) { resolved_input.value }),
          )
        },
      )
}

pub fn group_outputs_by_vesting_datum(
  validator_outputs: List<Output>,
) -> Dict<ByteArray, Pair<LinearVestingParameters, List<Output>>> {
  validator_outputs
    |> list.foldl(
        dict.new(),
        fn(output, acc) {
          expect InlineDatum(datum) = output.datum
          expect linear_params: LinearVestingParameters = datum
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
