use aiken/time.{PosixTime}

pub type LinearVestingParameters {
  //The time that value in the vesting utxo starts vesting
  start_time: PosixTime,
  //At which interval the value vests
  vest_frequency: PosixTime,
  //Number of vesting periods left (So after vest_periods*vest_frequency+start_time all assets are vested)
  vest_periods: Int,
  //Cliff time, tokens are not vested before this time
  cliff_time: PosixTime,
}
