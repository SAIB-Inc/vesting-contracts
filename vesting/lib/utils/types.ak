use linear_vesting/types.{LinearVestingParameters}

//Prefix of the reference nft asset id according to CIP-68
pub const reference_prefix = #"000643b0"

//Prefix of the nft asset id according to CIP-68
pub const user_nft_prefix = #"000de140"

//Prefix of the vesting nft asset name
pub const vesting_nft_prefix = @"CNCT_VESTING_"

//Image of the vesting nft
pub const vesting_nft_image = @"ipfs://aaaaaaa"

pub type Identifier {
  ReferenceNft
  UserNft
}

pub type LinearVestingPosition {
  metadata: List<(ByteArray, ByteArray)>,
  version: Int,
  extra: LinearVestingParameters,
}
