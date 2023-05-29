module meadow::vesting {
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use std::vector as vec;
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    // use sui::event;
    // Scaling constants
    const TOKEN_UPSCALING_FACTOR: u64 = 1_000_000_000;
    const PERCENTAGE_SCALE: u64 = 100_000;

    /// The one of a kind - created in the module initializer.
    struct VestingOperatorCapability has key {
        id: UID
    }

  

    /// A shared object. `key` ability is required.
    struct VestedDistributionPool<phantom MEADOW> has key {
        id: UID,
        user: address,
        amount: u64, 
        balance: Balance<MEADOW>,
        claimedAmount: u64, 
        currentPeriod: u64,
        periodUnlockPercentage: vector<u64>, // in a scale of 1% = 100,000
        unlockCooldownMs: u64, // in milliseconds
        lastUnlockTimestampMs: u64, // in milliseconds
        poolCreationTimestampMs: u64, // in milliseconds
    }

    /// Getter functions for the `VestedDistributionPool` object
    
    public entry fun get_vested_distribution_pool_user<MEADOW>(
      data: &mut VestedDistributionPool<MEADOW>,
    ): address {
      data.user
    }
  
    public entry fun get_vested_distribution_pool_amount<MEADOW>(
      data: &mut VestedDistributionPool<MEADOW>,
    ): u64 {
      balance::value(&data.balance)
    }

    public entry fun get_vested_distribution_pool_claimed_amount<MEADOW>(
      data: &mut VestedDistributionPool<MEADOW>,
    ): u64 {
      data.claimedAmount
    }

    public entry fun create_vested_distribution_pool<MEADOW>(
      _: &mut VestingOperatorCapability,
      recipient: address,
      rewardAmount: u64,
      tokens: &mut Coin<MEADOW>,
      periodUnlockPercentage: vector<u64>,
      unlockCooldownMs: u64,
      clock: &Clock,
      ctx: &mut TxContext,
    ) {

       let med_balance = coin::balance_mut<MEADOW>(tokens);
       let balance_for_user = balance::split<MEADOW>(med_balance, rewardAmount);

      transfer::transfer(VestedDistributionPool<MEADOW> {
        id: object::new(ctx),
        user: recipient,
        amount:rewardAmount,
        balance: balance_for_user,
        currentPeriod: 0,
        claimedAmount: 0,
        periodUnlockPercentage: periodUnlockPercentage,
        unlockCooldownMs: unlockCooldownMs,
        lastUnlockTimestampMs: clock::timestamp_ms(clock),
        poolCreationTimestampMs: clock::timestamp_ms(clock),
      }, recipient);
    }
    // public entry fun noclock_create_vested_distribution_pool<MEADOW>(
    //   _: &VestingOperatorCapability,
    //   tokens:  Coin<MEADOW>,
    //   periodUnlockPercentage: vector<u64>,
    //   unlockCooldownMs: u64,
    //   currentTimestamp: u64,
    //   ctx: &mut TxContext,
    // ) {

    //   let med_balance = coin::into_balance<MEADOW>(tokens);

    //   transfer::transfer(VestedDistributionPool<MEADOW> {
    //     id: object::new(ctx),
    //     user: tx_context::sender(ctx),
    //     amount: med_balance,
    //     currentPeriod: 0,
    //     claimedAmount: 0,
    //     periodUnlockPercentage: periodUnlockPercentage,
    //     unlockCooldownMs: unlockCooldownMs,
    //     lastUnlockTimestampMs: currentTimestamp,
    //     poolCreationTimestampMs: currentTimestamp,
    //   }, tx_context::sender(ctx));
    // }



    public entry fun claim_rewards_vested_distribution_pool<MEADOW>(
      data: &mut VestedDistributionPool<MEADOW>,
      clock: &Clock,
      ctx: &mut TxContext,
    ) {

      let currentTimestamp = clock::timestamp_ms(clock);

      // Check if the user has any rewards to claim
      assert!(data.claimedAmount < data.amount, 0);

      if(data.lastUnlockTimestampMs != data.poolCreationTimestampMs)
      {
        // Only perform these checks if the user has already claimed some rewards
        // Check if the user has waited long enough to claim the rewards
        let timeSinceLastUnlock = currentTimestamp - data.lastUnlockTimestampMs;
        assert!(timeSinceLastUnlock >= data.unlockCooldownMs, 0);
      };

      // There is a situation where user might not claim their rewards, skippiing periods. We need to calculate how many 
      // periods have passed since the last claim and update the current period accordingly.

      let elligiblePeriodCount = (currentTimestamp - data.lastUnlockTimestampMs) / data.unlockCooldownMs;
      let elligiblePeriodCountClone = (currentTimestamp - data.lastUnlockTimestampMs) / data.unlockCooldownMs;

      // This is the case where the user has not claimed any rewards yet. So they are elligible to claim the first period.
      if(data.lastUnlockTimestampMs == data.poolCreationTimestampMs) elligiblePeriodCount = 1;

      // Accout for the situation in where the user missed the first period.
      if(data.lastUnlockTimestampMs == data.poolCreationTimestampMs && elligiblePeriodCountClone > 0 ) elligiblePeriodCount = elligiblePeriodCountClone;


      // Loop through the rewarding period `elligiblePeriodCount` times and reward accordingly
      
      let i = 0;

      while (i < elligiblePeriodCount) {
        // Calculate the amount of tokens to be unlocked
        let unlockPercentage = vec::borrow(&data.periodUnlockPercentage, data.currentPeriod);
        let amountToBeUnlocked = (data.amount * *unlockPercentage) / PERCENTAGE_SCALE;

        // Update the claimed amount
        data.claimedAmount = data.claimedAmount + amountToBeUnlocked;

        let coins = coin::take(&mut data.balance, amountToBeUnlocked, ctx);
        transfer::public_transfer(coins, tx_context::sender(ctx));

        // Update the current period
        data.currentPeriod = data.currentPeriod + 1;

        i = i + 1;
      };

      // Update the last unlock timestamp
      data.lastUnlockTimestampMs = currentTimestamp;
    }


    public entry fun noclock_claim_rewards_vested_distribution_pool<MEADOW>(
      data: &mut VestedDistributionPool<MEADOW>,
      currentTimestamp: u64,
    ) {

      // Check if the user has any rewards to claim
      assert!(data.claimedAmount < balance::value(&data.balance) , 0);

      if(data.lastUnlockTimestampMs != data.poolCreationTimestampMs)
      {
        // Only perform these checks if the user has already claimed some rewards
        // Check if the user has waited long enough to claim the rewards
        // let timeSinceLastUnlock = currentTimestamp - data.lastUnlockTimestampMs;
        // assert!(timeSinceLastUnlock >= data.unlockCooldownMs, 0);
      };

      // There is a situation where user might not claim their rewards, skippiing periods. We need to calculate how many 
      // periods have passed since the last claim and update the current period accordingly.

      let elligiblePeriodCount = (currentTimestamp - data.lastUnlockTimestampMs) / data.unlockCooldownMs;
      let elligiblePeriodCountClone = (currentTimestamp - data.lastUnlockTimestampMs) / data.unlockCooldownMs;

      // This is the case where the user has not claimed any rewards yet. So they are elligible to claim the first period.
      if(data.lastUnlockTimestampMs == data.poolCreationTimestampMs) elligiblePeriodCount = 1;

      // Accout for the situation in where the user missed the first period.
      if(data.lastUnlockTimestampMs == data.poolCreationTimestampMs && elligiblePeriodCountClone > 0 ) elligiblePeriodCount = elligiblePeriodCountClone;


      // Loop through the rewarding period `elligiblePeriodCount` times and reward accordingly
      
      let i = 0;

      while (i < elligiblePeriodCount) {
        // Calculate the amount of tokens to be unlocked

        std::debug::print(&data.periodUnlockPercentage);
        std::debug::print(&data.currentPeriod);

        let unlockPercentage = vec::borrow(&data.periodUnlockPercentage, data.currentPeriod);
        let amountToBeUnlocked = (balance::value(&data.balance) * *unlockPercentage) / PERCENTAGE_SCALE;

        // Update the claimed amount
        data.claimedAmount = data.claimedAmount + amountToBeUnlocked;

        // Update the current period
        data.currentPeriod = data.currentPeriod + 1;

        i = i + 1;
      };

      // Update the last unlock timestamp
      data.lastUnlockTimestampMs = currentTimestamp;
      
    }
    

    
    /// This function is only called once on module publish.
    /// Use it to make sure something has happened only once, like
    /// here - only module author will own a version of a
    /// `ICOOperatorCapability` struct.
    fun init(ctx: &mut TxContext) {
        transfer::transfer(VestingOperatorCapability {
            id: object::new(ctx),
        }, tx_context::sender(ctx));    
    }
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

}

#[test_only]
module meadow::vestingTest {

  use sui::test_scenario::{Self, Scenario};
  // use sui::coin::{Self, Coin};
  // use sui::balance::{Self, Balance};
  // use sui::sui::SUI;
  use medvesting::medvesting::{Self, VestingOperatorCapability, VestedDistributionPool};
  // use std::debug;
  use std::vector as vec;
  // use sui::transfer;

  fun init_contract_for_testing(scenario: &mut Scenario, user: address) {
    test_scenario::next_tx(scenario, user);
    {
      medvesting::init_for_testing(
        test_scenario::ctx(scenario)
       );
    };
  }
  fun create_vested_distribution_pool(scenario: &mut Scenario, user: address, currentTimestamp: u64) {
    test_scenario::next_tx(scenario, user);
    {
      let operator_cap_val = test_scenario::take_from_sender<VestingOperatorCapability>(scenario);
      let operator_cap = &mut operator_cap_val;
      let periodUnlockSchedule = vec::empty<u64>();
      vec::push_back(&mut periodUnlockSchedule, 25000);
      vec::push_back(&mut periodUnlockSchedule, 25000);
      vec::push_back(&mut periodUnlockSchedule, 25000);
      vec::push_back(&mut periodUnlockSchedule, 25000); // 25% 

      medvesting::noclock_create_vested_distribution_pool(
        operator_cap, 
        10000, // amount
        periodUnlockSchedule, 
        1000, // unlock cooldown
        currentTimestamp,
        test_scenario::ctx(scenario) );

      test_scenario::return_to_sender(scenario, operator_cap_val);
    };
  }
  fun create_vested_distribution_pool_rtc_60sec(scenario: &mut Scenario, user: address, currentTimestamp: u64) {
    test_scenario::next_tx(scenario, user);
    {
      let operator_cap_val = test_scenario::take_from_sender<VestingOperatorCapability>(scenario);
      let operator_cap = &mut operator_cap_val;
      let periodUnlockSchedule = vec::empty<u64>();
      vec::push_back(&mut periodUnlockSchedule, 25000);
      vec::push_back(&mut periodUnlockSchedule, 25000);
      vec::push_back(&mut periodUnlockSchedule, 25000);
      vec::push_back(&mut periodUnlockSchedule, 25000); // 25% 

      medvesting::noclock_create_vested_distribution_pool(
        operator_cap, 
        10000, // amount
        periodUnlockSchedule, 
        60000, // unlock cooldown
        currentTimestamp,
        test_scenario::ctx(scenario) );

      test_scenario::return_to_sender(scenario, operator_cap_val);
    };
  }

  fun create_vested_distribution_pool_two_months_cliff(scenario: &mut Scenario, user: address, currentTimestamp: u64) {
    test_scenario::next_tx(scenario, user);
    {
      let operator_cap_val = test_scenario::take_from_sender<VestingOperatorCapability>(scenario);
      let operator_cap = &mut operator_cap_val;
      let periodUnlockSchedule = vec::empty<u64>();
      vec::push_back(&mut periodUnlockSchedule, 0);
      vec::push_back(&mut periodUnlockSchedule, 0);
      vec::push_back(&mut periodUnlockSchedule, 50000);
      vec::push_back(&mut periodUnlockSchedule, 50000); // 25% 

      medvesting::noclock_create_vested_distribution_pool(
        operator_cap, 
        10000, // amount
        periodUnlockSchedule, 
        1000, // unlock cooldown
        currentTimestamp,
        test_scenario::ctx(scenario) );

      test_scenario::return_to_sender(scenario, operator_cap_val);
    };
  }



  fun claim_vested_distribution_pool(scenario: &mut Scenario, user: address, timestamp: u64) {
    test_scenario::next_tx(scenario, user);
    {

      let poolData = test_scenario::take_from_sender<VestedDistributionPool>(scenario);
      let poolDataMutable = &mut poolData;
 
      medvesting::noclock_claim_rewards_vested_distribution_pool(
        poolDataMutable,
        timestamp
        );

      test_scenario::return_to_sender(scenario, poolData);
    };
  }

  fun assert_claimed_amound_vested_distribution_pool(scenario: &mut Scenario, user: address, amount: u64) {
    test_scenario::next_tx(scenario, user);
    {

      let poolData = test_scenario::take_from_sender<VestedDistributionPool>(scenario);
      let poolDataMutable = &mut poolData;
 
      let claimedAmount = medvesting::get_vested_distribution_pool_claimed_amount(
        poolDataMutable,
        );

      // std::debug::print(&claimedAmount);

      assert!(claimedAmount == amount, 0);

      test_scenario::return_to_sender(scenario, poolData);
    };
  }

  #[test]
  fun attempt_first_claim_in_vested_pool_25percent() {
    let user1 = @0x1;
    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;

    init_contract_for_testing(scenario, user1);
    create_vested_distribution_pool(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 1);
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 2500);

    test_scenario::end(scenario_val);
  }

  #[test]
  #[expected_failure]
  fun attempt_second_claim_in_vested_pool_without_time_passing() {
    let user1 = @0x1;
    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;

    init_contract_for_testing(scenario, user1);
    create_vested_distribution_pool(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 1);
    claim_vested_distribution_pool(scenario, user1, 500); // 1000 seconds should pass instead of 100
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 2500);

    test_scenario::end(scenario_val);
  }
  #[test]
  fun attempt_second_claim_in_vested_pool_with_time_passing() {
    let user1 = @0x1;
    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;

    init_contract_for_testing(scenario, user1);
    create_vested_distribution_pool(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 1);
    claim_vested_distribution_pool(scenario, user1, 1001);
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 5000);

    test_scenario::end(scenario_val);
  }
  #[test]
  fun attempt_third_claim_in_vested_pool_with_time_passing() {
    let user1 = @0x1;
    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;

    init_contract_for_testing(scenario, user1);
    create_vested_distribution_pool(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 1);
    claim_vested_distribution_pool(scenario, user1, 1001);
    claim_vested_distribution_pool(scenario, user1, 2001);
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 7500);

    test_scenario::end(scenario_val);
  }
  #[test]
  fun attempt_third_claim_in_vested_pool_with_missed_second_claim() {
    let user1 = @0x1;
    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;

    init_contract_for_testing(scenario, user1);
    create_vested_distribution_pool(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 1);
    // claim_vested_distribution_pool(scenario, user1, 1001); <--- simulating missed claim
    claim_vested_distribution_pool(scenario, user1, 2001);
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 7500);

    test_scenario::end(scenario_val);
  }
  #[test]
  #[expected_failure]
  fun attempt_cannot_claim_in_vested_pool_when_nothing_is_left() {
    let user1 = @0x1;
    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;

    init_contract_for_testing(scenario, user1);
    create_vested_distribution_pool(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 1);
    claim_vested_distribution_pool(scenario, user1, 1001);
    claim_vested_distribution_pool(scenario, user1, 2001);
    claim_vested_distribution_pool(scenario, user1, 3001);
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 10000);
    claim_vested_distribution_pool(scenario, user1, 4001); // <----- should faild

    test_scenario::end(scenario_val);
  }

  #[test]
  fun attempt_claim_in_vested_pool_with_two_months_cliff() {
    let user1 = @0x1;
    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;

    init_contract_for_testing(scenario, user1);
    create_vested_distribution_pool_two_months_cliff(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 1);// <-- 2 months cliff
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 1001);// <-- 2 months cliff
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 2001); 
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 5000);

    test_scenario::end(scenario_val);
  }
  #[test]
  fun attempt_second_claim_in_vested_pool_with_two_months_cliff() {
    let user1 = @0x1;
    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;

    init_contract_for_testing(scenario, user1);
    create_vested_distribution_pool_two_months_cliff(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 1);// <-- 2 months cliff
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 1001);// <-- 2 months cliff
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 2001); 
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 5000);
    claim_vested_distribution_pool(scenario, user1, 3001); 
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 10000);

    test_scenario::end(scenario_val);
  }
  #[test]
  fun attempt_second_claim_in_vested_pool_with_two_months_cliff_with_missed_first_claim() {
    let user1 = @0x1;
    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;

    init_contract_for_testing(scenario, user1);
    create_vested_distribution_pool_two_months_cliff(scenario, user1, 0);
    // claim_vested_distribution_pool(scenario, user1, 1);// <-- 2 months cliff
    // assert_claimed_amound_vested_distribution_pool(scenario, user1, 0);
    // claim_vested_distribution_pool(scenario, user1, 1001);// <-- 2 months cliff
    // assert_claimed_amound_vested_distribution_pool(scenario, user1, 0);
    // claim_vested_distribution_pool(scenario, user1, 2001); 
    // assert_claimed_amound_vested_distribution_pool(scenario, user1, 5000);
    claim_vested_distribution_pool(scenario, user1, 4000); 
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 10000);

    test_scenario::end(scenario_val);
  }

  #[test]
  fun attempt_first_claim_in_vested_pool_25percent_rtc_time() {
    let user1 = @0x1;
    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;

    init_contract_for_testing(scenario, user1);
    create_vested_distribution_pool_rtc_60sec(scenario, user1, 0);
    claim_vested_distribution_pool(scenario, user1, 60000);
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 2500);
    claim_vested_distribution_pool(scenario, user1, 119000);
    assert_claimed_amound_vested_distribution_pool(scenario, user1, 5000);

    test_scenario::end(scenario_val);
  }
  
}


