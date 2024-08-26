use aiken/bytearray.{concat, drop, take}
use aiken/cbor.{serialise}
use aiken/dict.{size, to_pairs}
use aiken/hash.{blake2b_256}
use aiken/list.{all, filter, foldr, length}
use aiken/math.{abs}
use aiken/transaction.{
  Input, Mint, Output, OutputReference, ScriptContext, Spend, WithdrawFrom,
}
use aiken/transaction/credential.{Inline, ScriptCredential}
use aiken/transaction/value.{MintedValue, minted_to_dict}
use utils/types.{
  Identifier, ReferenceNft, UserNft, reference_prefix, user_nft_prefix,
}

pub fn get_validator_hash(context: ScriptContext) {
  when context.purpose is {
    Spend(self_ref) -> {
      let inputs = context.transaction.inputs
      let self_inputs =
        inputs |> list.filter(fn(input) { input.output_reference == self_ref })
      expect Some(self_input) = self_inputs |> list.head()
      expect ScriptCredential(validator_hash) =
        self_input.output.address.payment_credential
      validator_hash
    }
    Mint(policy_id) -> policy_id
    WithdrawFrom(Inline(ScriptCredential(stake_creds))) -> stake_creds
    _ -> #""
  }
}

pub fn get_spend_context_output_reference(
  context: ScriptContext,
) -> Option<OutputReference> {
  when context.purpose is {
    Spend(output_ref) -> Some(output_ref)
    _ -> None
  }
}

pub fn get_context_unique_identifier(context: ScriptContext) -> ByteArray {
  // Serialise the transaction to get a unique identifier for the context (?)
  blake2b_256(serialise(context.transaction))
}

pub fn find_script_inputs(
  inputs: List<Input>,
  validator_hash: ByteArray,
) -> List<Input> {
  inputs
    |> list.filter(
        fn(input) {
          expect ScriptCredential(input_credential) =
            input.output.address.payment_credential
          input_credential == validator_hash
        },
      )
}

pub fn verify_cip68_pairs(
  minted_value: MintedValue,
  policy_id: ByteArray,
) -> Bool {
  let minted_value_dict = minted_value |> minted_to_dict()
  expect Some(minted_assets) = minted_value_dict |> dict.get(policy_id)
  let reference_nfts =
    minted_assets
      |> to_pairs()
      |> filter(fn(a) { take(a.1st, 4) == reference_prefix })

  let reference_match =
    reference_nfts
      |> all(
          fn(a) {
            expect Some(user_nft_amount) =
              minted_assets |> dict.get(concat(user_nft_prefix, drop(a.1st, 4)))
            let absolute_amount = abs(a.2nd)
            expect absolute_amount == 1
            a.2nd == user_nft_amount
          },
        )
  let expected_nft_count = length(reference_nfts) * 2
  and {
    reference_match,
    expected_nft_count == size(minted_assets),
  }
}

pub fn ident_to_asset_name(identifier: ByteArray, t: Identifier) -> ByteArray {
  let prefix =
    when t is {
      ReferenceNft -> reference_prefix
      UserNft -> user_nft_prefix
    }

  let unique_nft_name =
    foldr(
      [prefix, bytearray.from_string(@"CNCT_VESTING_"), identifier],
      #"",
      fn(a, b) { concat(a, b) },
    )
      |> take(32)

  unique_nft_name
}
