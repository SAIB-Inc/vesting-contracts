use aiken/hash.{Blake2b_224, Hash}
use aiken/merkle_patricia_forestry.{Proof}
use aiken/transaction/credential.{Script}
use aiken/transaction/value.{Value}
use sundae/multisig.{MultisigScript}

pub type TreasuryDatum {
  owner: MultisigScript,
  treasury_root_hash: ByteArray,
}

pub type TreasuryRedeemer {
  Claim { proof: Proof, entry: ClaimEntry }
  AdminWithdraw
}

pub type ClaimEntry {
  claimant: MultisigScript,
  vesting_value: Value,
  direct_value: Value,
  vesting_parameters: ByteArray,
  vesting_program: Hash<Blake2b_224, Script>,
}
