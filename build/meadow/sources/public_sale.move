module meadow::public_sale {
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use std::vector as vec;
    use sui::clock::{Self, Clock};
    use sui::event;
    // use std::debug;

    // Error codes

    const EPresaleNotStarted: u64 = 0;
    const EPresaleEnded: u64 = 1;
    const ECannotEndAlreadyEndedPresale: u64 = 2;
    const EInsufficientPaymentSent: u64 = 4;
    const EUserDataAlreadyCreated : u64 = 5;
    const EAddressAlreadyWhitelisted : u64 = 6;
    const EInvalidTimeframe: u64 = 7;
    const EAddressNotWhitelisted : u64 = 8;

    const WITHDRAW_FUNDS_WALLET : address = @0x4f7105a8f44591f636ac8e6c9b22cac9c406f833379d7f51797b7b83e09915a6;


    // Events

    struct SingleAddressAddedToWhitelist has copy, drop {
        wallet: address
    }

    struct MultipleAddressAddedToWhitelist has copy, drop {
        wallets: vector<address>
    }

    struct SuiContributionRecieved has copy, drop {
        wallet: address,
        amount: u64
    }

    struct RewardsCalculated has copy, drop {
        wallet: address,
        tokens: u64,
        bonus: u64,
        refundableSui: u64
    }

    struct FundsWithdrawn has copy, drop {
        wallet: address,
        amount: u64
    }

    struct PresaleEnded has copy, drop {
        totalSuiDeposited: u64,
    }

    // Scaling constants
    const TOKEN_UPSCALING_FACTOR: u64 = 1_000_000_000;

    /// The one of a kind - created in the module initializer.
    struct ICOOperatorCapability has key {
        id: UID
    }

    /// A shared object. `key` ability is required.
    struct PresaleData has key {
        id: UID,
        icoStartTimestamp: u64,
        icoEndTimestamp: u64,
        suiPerToken: u64,
        totalTokensForSale: u64,
        totalSuiDeposited: Balance<SUI>,
        amountToBeRaisedSui: u64,
        actualAmountRaisedSui: u64,
        minimumContributionSui: u64,
        isPresaleActive: bool,
        whitelistedAddresses: vector<address>,
        contributors: vector<address>,
        bonusRewardPool: u64,
        bonusDepositPool: u64,
        testTotalSuiDeposited: u64,
    }

    /// Getter functions for the `PresaleData` object
  
    public entry fun get_ico_start_timestamp(
      data: &mut PresaleData,
    ): u64 {
      data.icoStartTimestamp
    }

    public entry fun get_ico_end_timestamp(
      data: &mut PresaleData,
    ): u64 {
      data.icoEndTimestamp
    }

    public entry fun get_sui_per_token(
      data: &mut PresaleData,
    ): u64 {
      data.suiPerToken
    }

    public entry fun get_total_tokens_for_sale(
      data: &mut PresaleData,
    ): u64 {
      data.totalTokensForSale
    }

    public entry fun get_amount_to_be_raised_sui(
      data: &mut PresaleData,
    ): u64 {
      data.amountToBeRaisedSui
    }

    public entry fun get_actual_amount_raised_sui(
      data: &mut PresaleData,
    ): u64 {
      data.actualAmountRaisedSui
    }

    public entry fun get_minimum_contribution_sui(
      data: &mut PresaleData,
    ): u64 {
      data.minimumContributionSui
    }

    public entry fun get_is_presale_active(
      data: &mut PresaleData,
    ): bool {
      data.isPresaleActive
    }

    public entry fun get_whitelisted_addresses(
      data: &mut PresaleData,
    ): vector<address> {
      data.whitelistedAddresses
    }

    public entry fun get_is_whitelisted(
      data: &mut PresaleData,
      address: address,
    ): bool {
      vec::contains(&data.whitelistedAddresses, &address)
    }

    public entry fun get_bonus_reward_pool(
      data: &mut PresaleData,
    ): u64 {
      data.bonusRewardPool
    }

    public entry fun get_bonus_deposit_pool(
      data: &mut PresaleData,
    ): u64 {
      data.bonusDepositPool
    }


    struct UserData has key {
      id: UID,
      wallet: address,
      investedSui: u64,
      refundableSui: u64,
      calculatedTokensReward: u64,
      calculatedBonusReward: u64,
    }


    public entry fun get_sui_balance(
      user: &mut UserData,
    ): u64 {
      user.investedSui
    }

    public entry fun get_refundable_sui(
      user: &mut UserData,
    ): u64 {
      user.refundableSui
    }

    public entry fun get_calculated_tokens_reward(
      user: &mut UserData,
    ): u64 {
      user.calculatedTokensReward
    }

    public entry fun get_calculated_bonus_reward(
      user: &mut UserData,
    ): u64 {
      user.calculatedBonusReward
    }


    
    /// This function is only called once on module publish.
    /// Use it to make sure something has happened only once, like
    /// here - only module author will own a version of a
    /// `ICOOperatorCapability` struct.
    fun init(ctx: &mut TxContext) {

        transfer::transfer(ICOOperatorCapability {
            id: object::new(ctx),
        }, tx_context::sender(ctx));

        // Share the `PresaleData` object so everyone can access it

        transfer::share_object(PresaleData {
          id: object::new(ctx),
          icoStartTimestamp: 0,
          icoEndTimestamp: 1984276317 * 1000,
          suiPerToken: 1_000_000, // for testing we're using a scale of 1,000,000,000
          totalTokensForSale: 1_450_000_000 * TOKEN_UPSCALING_FACTOR,
          totalSuiDeposited: balance::zero(),
          amountToBeRaisedSui: 1_450_000 * TOKEN_UPSCALING_FACTOR,
          actualAmountRaisedSui: 0,
          minimumContributionSui: 1,
          isPresaleActive: true,
          whitelistedAddresses: vec::empty(),
          contributors: vec::empty(),
          bonusRewardPool: 1_130_000 * TOKEN_UPSCALING_FACTOR,
          bonusDepositPool: 0, // 0 tokens initially
          testTotalSuiDeposited: 0,
        })
    }

    public entry fun add_single_whitelist_entry(
      _: &ICOOperatorCapability,
      data: &mut PresaleData,
      address: address,
    ) {

      // Check if the address is already whitelisted
      assert!(vec::contains(&data.whitelistedAddresses, &address) == false, EAddressAlreadyWhitelisted);

      vec::push_back(&mut data.whitelistedAddresses, address);
      event::emit(SingleAddressAddedToWhitelist { wallet: address });
    }

    public entry fun remove_whitelist_entry(
      _: &ICOOperatorCapability,
      data: &mut PresaleData,
      address: address,
    ) {

      // Check if the address is already whitelisted
      assert!(vec::contains(&data.whitelistedAddresses, &address) == true, EAddressNotWhitelisted);

      // Find the index of the address in the whitelist array
      let (_isWhitelisted, index) = vec::index_of(&data.whitelistedAddresses, &address);

      // Remove the address from the whitelist
      vec::remove(&mut data.whitelistedAddresses, index);
      event::emit(SingleAddressAddedToWhitelist { wallet: address });
    }
    
    public entry fun add_multiple_whitelist_entries(
      _: &ICOOperatorCapability,
      data: &mut PresaleData,
      addresses: vector<address>,
    ) {
      vec::append(&mut data.whitelistedAddresses, addresses);
      event::emit(MultipleAddressAddedToWhitelist { wallets: addresses });
    }


    public entry fun end_presale(
      _: &ICOOperatorCapability,
      data: &mut PresaleData,
    ) {
      // Make sure the presale has not ended yet
      assert!(data.isPresaleActive, ECannotEndAlreadyEndedPresale);
      

      data.isPresaleActive = false;

      event::emit(PresaleEnded { 
        totalSuiDeposited: balance::value(&data.totalSuiDeposited)
      });
    }

    public entry fun change_ico_timeframes(
      _: &ICOOperatorCapability,
      data: &mut PresaleData,
      icoStartTimestamp: u64,
      icoEndTimestamp: u64,
    ) {

      // Check if the time sent is valid
      assert!(icoEndTimestamp > icoStartTimestamp, EInvalidTimeframe);
      
      data.icoStartTimestamp = icoStartTimestamp;
      data.icoEndTimestamp = icoEndTimestamp;
    }

    public entry fun create_user_data(
      data: &mut PresaleData,
      wallet: address,
      ctx: &mut TxContext,
    ) {

      assert!(vec::contains(&data.contributors, &tx_context::sender(ctx)) == false, EUserDataAlreadyCreated);
      vec::push_back(&mut data.contributors, tx_context::sender(ctx));

      transfer::transfer(UserData {
        id: object::new(ctx),
        wallet: wallet,
        investedSui: 0,
        refundableSui: 0,
        calculatedTokensReward: 0,
        calculatedBonusReward: 0,
      }, tx_context::sender(ctx));
    }

    public entry fun purchase_tokens(
      data: &mut PresaleData,
      user: &mut UserData,
      coins: &mut Coin<SUI>,
      amount: u64,
      clock: &Clock,
      ctx: &mut TxContext,
    ) {


      let currentTimestamp = clock::timestamp_ms(clock);

      // Make the necessary checks
      assert!(amount > data.minimumContributionSui, EInsufficientPaymentSent);
      assert!(currentTimestamp >= data.icoStartTimestamp, EPresaleNotStarted);
      assert!(currentTimestamp <= data.icoEndTimestamp, EPresaleEnded);
      assert!(data.isPresaleActive, EPresaleEnded);

      let sui_balance = coin::balance_mut(coins);
      let payment = balance::split(sui_balance, amount);

      user.investedSui = user.investedSui + balance::value(&payment);

      let purchaseSuiValue = balance::value(&payment);

      event::emit(SuiContributionRecieved { wallet: tx_context::sender(ctx), amount: balance::value(&payment) });

      // Transfer the SUI to the contract
      balance::join(&mut data.totalSuiDeposited, payment);

      data.actualAmountRaisedSui = data.actualAmountRaisedSui + purchaseSuiValue;

    }

    #[test_only]
    public entry fun test_purchase_tokens(
      data: &mut PresaleData,
      user: &mut UserData,
      amount: u64,
    ) {

      user.investedSui = user.investedSui + amount;

      let purchaseSuiValue = amount;

      // Transfer the SUI to the contract
      data.testTotalSuiDeposited = data.testTotalSuiDeposited + amount;
      data.actualAmountRaisedSui = data.actualAmountRaisedSui + purchaseSuiValue;

    }

    /// The user can check how many rewards they are elligible for considering the current pool 

    public entry fun calculate_elligible_rewards(
      data: &mut PresaleData,
      user: &mut UserData,
      ctx: &mut TxContext,
    ) {

      let reward = calculate_reward(
        user.investedSui,
        data.suiPerToken,
        data.totalTokensForSale,
        data.amountToBeRaisedSui,
        data.actualAmountRaisedSui,
      );

      let refundableSuiAmount =
        calculate_refundable_reward(
          user.investedSui,
          data.suiPerToken,
          data.totalTokensForSale,
          data.amountToBeRaisedSui,
          data.actualAmountRaisedSui,
        );
      

      let isUserWhitelisted = get_is_whitelisted(data, tx_context::sender(ctx));

      if(isUserWhitelisted) {

        user.calculatedBonusReward = calculate_bonus_reward(
          user.investedSui,
          data.bonusRewardPool,
          data.testTotalSuiDeposited
          // balance::value(&data.totalSuiDeposited),
        );

      };

      // Set the refundable sui in the user's struct
      user.refundableSui = refundableSuiAmount;

      // Set the reward in the user's struct
      user.calculatedTokensReward = reward;

      event::emit(RewardsCalculated { wallet: tx_context::sender(ctx), tokens: reward, bonus: user.calculatedBonusReward, refundableSui: refundableSuiAmount });
    }

    fun calculate_reward(
      suiIn: u64,
      suiPerToken: u64,
      totalTokensForSale: u64,
      amountToBeRaisedSui: u64,
      actualAmountRaisedSui: u64,
    ): u64 {


      // Presale has been sold, or oversold
      if(actualAmountRaisedSui >= amountToBeRaisedSui)
      {
      let shareFromInvestmentPool = suiIn * 10_000_000 / actualAmountRaisedSui;
      let claimableTokens = shareFromInvestmentPool * (totalTokensForSale / TOKEN_UPSCALING_FACTOR);
      let claimableTokensDownscaled = claimableTokens / 10_000_000;

      let claimableTokensScaledToSuiDecimals = claimableTokensDownscaled * TOKEN_UPSCALING_FACTOR;

        claimableTokensScaledToSuiDecimals
      }
      else {
        // Presale has not been sold yet
        let claimableTokens = (suiIn / suiPerToken) * TOKEN_UPSCALING_FACTOR;
        claimableTokens
      }

    }


    fun calculate_refundable_reward(
      suiIn: u64,
      suiPerToken: u64,
      totalTokensForSale: u64,
      amountToBeRaisedSui: u64,
      actualAmountRaisedSui: u64,
    ): u64 {


      let tokens_reward = calculate_reward(
        suiIn,
        suiPerToken,
        totalTokensForSale,
        amountToBeRaisedSui,
        actualAmountRaisedSui,
      );

      let _refundableTokens = 0;
    
      let tokensValueInSui = (tokens_reward / 10_000_000 * suiPerToken) / TOKEN_UPSCALING_FACTOR * 10_000_000;

      if (tokensValueInSui > suiIn) {
        _refundableTokens = 0;
      } else {
        _refundableTokens = (suiIn - tokensValueInSui);
      };

      _refundableTokens
      
    }

    fun calculate_bonus_reward(
      suiIn: u64,
      bonusRewardPoolValue: u64,
      bonusDepositPoolValue: u64,
    ): u64 {

      let shareFromRewardPool = suiIn * 10_000 / bonusDepositPoolValue;
      let claimableTokens = shareFromRewardPool * bonusRewardPoolValue;
      let claimableTokensDownscaled = claimableTokens / 10_000;
      claimableTokensDownscaled

    }

    public entry fun withdraw_funds(
      data: &mut PresaleData,
      ctx: &mut TxContext,
    ) {
      let amount = balance::value(&data.totalSuiDeposited);
      let coins = coin::take(&mut data.totalSuiDeposited, amount, ctx);
      transfer::public_transfer(coins, WITHDRAW_FUNDS_WALLET);
      event::emit(FundsWithdrawn { wallet: WITHDRAW_FUNDS_WALLET, amount: amount });
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun set_actual_amount_raised(
      data: &mut PresaleData,
      amount: u64,
    ) {
        data.actualAmountRaisedSui = amount;
    }

}

// #[test_only]
// module aurora::auroraIcoTest {

//   use sui::test_scenario::{Self, Scenario};
//   // use sui::coin::{Self, Coin};
//   // use sui::balance::{Self, Balance};
//   // use sui::sui::SUI;
//   use aurora::auroraIco::{Self, PresaleData, UserData, ICOOperatorCapability };
//   use sui::clock::{Self};
//   // use std::debug;
//   // use std::vector as vec;
//   // use sui::transfer;

//   const TOKEN_UPSCALING_FACTOR: u64 = 1_000_000_000;
//   const HIDE_DEBUG_MESSAGES: bool = false;

//   fun initialize_user_data(scenario: &mut Scenario, user: address) {
//     // User1 initializes their user object
//     test_scenario::next_tx(scenario, user);
//     {
//       let data_val = test_scenario::take_shared<PresaleData>(scenario);
//       let data = &mut data_val;
//       let ctx = test_scenario::ctx(scenario);

//       // Attempt to create user object firstf

//       auroraIco::create_user_data(data, user, ctx);

//       test_scenario::return_shared(data_val);
//     };
//   }

//   fun add_single_wallet_to_whitelist(scenario: &mut Scenario, user: address, wallet: address) {
//    // Attempt to add a single user to the whitelist
//   test_scenario::next_tx(scenario, user);
//   {

//     let data_val = test_scenario::take_shared<PresaleData>(scenario);
//     let data = &mut data_val;


//     let presale_owner_cap_val = test_scenario::take_from_sender<ICOOperatorCapability>(scenario);
//     let presale_owner_cap = &mut presale_owner_cap_val;

//     auroraIco::add_single_whitelist_entry(
//       presale_owner_cap,
//       data,
//       wallet,
//     );

//     test_scenario::return_to_sender(scenario, presale_owner_cap_val);
//     test_scenario::return_shared(data_val);
//   };
//   }

//   fun remove_whitelist_entry(scenario: &mut Scenario, user: address, wallet: address) {
//    // Attempt to add a single user to the whitelist
//   test_scenario::next_tx(scenario, user);
//   {

//     let data_val = test_scenario::take_shared<PresaleData>(scenario);
//     let data = &mut data_val;


//     let presale_owner_cap_val = test_scenario::take_from_sender<ICOOperatorCapability>(scenario);
//     let presale_owner_cap = &mut presale_owner_cap_val;

//     auroraIco::remove_whitelist_entry(
//       presale_owner_cap,
//       data,
//       wallet,
//     );

//     test_scenario::return_to_sender(scenario, presale_owner_cap_val);
//     test_scenario::return_shared(data_val);
//   };
//   }

//   fun buy_tokens(scenario: &mut Scenario, user: address, amount: u64) {
//     test_scenario::next_tx(scenario, user);
//     {
//       let data_val = test_scenario::take_shared<PresaleData>(scenario);
//       let data = &mut data_val;
//       let userData = test_scenario::take_from_sender<UserData>(scenario);
//       let userDataMutable = &mut userData;

//       // Purchase tokens

//       auroraIco::test_purchase_tokens(
//         data, 
//         userDataMutable, 
//         amount,
//       );

//       // assert!(balance::value(&settings.suiBalance) == 10, 0);

//       test_scenario::return_to_sender(scenario, userData);
//       test_scenario::return_shared(data_val);
//     };
//   }

//   fun set_actual_amount_raised(scenario: &mut Scenario, user: address, amount: u64) {
//     test_scenario::next_tx(scenario, user);
//     {
//       let data_val = test_scenario::take_shared<PresaleData>(scenario);
//       let data = &mut data_val;

//       auroraIco::set_actual_amount_raised(
//         data,
//         amount,
//       );

//       let amountRaised = auroraIco::get_actual_amount_raised_sui(data);
//       assert!(amountRaised == amount, 0);

//       test_scenario::return_shared(data_val);
//     };
//   }

//   fun calculate_user_reward(scenario: &mut Scenario, user: address) {
//     test_scenario::next_tx(scenario, user);
//     {
//       let data_val = test_scenario::take_shared<PresaleData>(scenario);
//       let data = &mut data_val;
//       let userData = test_scenario::take_from_sender<UserData>(scenario);
//       let userDataMutable = &mut userData;

//       // Purchase tokens

//       let ctx = test_scenario::ctx(scenario);
//       auroraIco::calculate_elligible_rewards(
//         data, 
//         userDataMutable, 
//         ctx,
//       );

//       // assert!(balance::value(&settings.suiBalance) == 10, 0);

//       test_scenario::return_to_sender(scenario, userData);
//       test_scenario::return_shared(data_val);
//     };
//   }

//   fun init_contract_for_resting(scenario: &mut Scenario, user: address) {
//     test_scenario::next_tx(scenario, user);
//     {
//       auroraIco::init_for_testing(test_scenario::ctx(scenario));
//     };
//   }

//   fun assert_user_sui_balance(scenario: &mut Scenario, user: address, amount: u64) {
//     test_scenario::next_tx(scenario, user ); 
//     {
//       let userData = test_scenario::take_from_sender<UserData>(scenario);
//       let userDataMutable = &mut userData;

//       if(!HIDE_DEBUG_MESSAGES) {
//         std::debug::print(&111111);
//         std::debug::print(&auroraIco::get_refundable_sui(userDataMutable));
//       };
      

//       assert!(auroraIco::get_refundable_sui(userDataMutable) == amount, 0);


//       test_scenario::return_to_sender(scenario, userData);
//     };
//   }

//   fun assert_user_token_balance(scenario: &mut Scenario, user: address, amount: u64) {
//     test_scenario::next_tx(scenario, user ); 
//     {
//       let userData = test_scenario::take_from_sender<UserData>(scenario);
//       let userDataMutable = &mut userData;

//       if(!HIDE_DEBUG_MESSAGES) {
//         std::debug::print(&222222);
//         std::debug::print(&auroraIco::get_calculated_tokens_reward(userDataMutable));
//       };
//       assert!(auroraIco::get_calculated_tokens_reward(userDataMutable) == amount, 0);


//       test_scenario::return_to_sender(scenario, userData);
//     };
//   }
//   fun assert_wallet_whitelisted(scenario: &mut Scenario, user: address) {
//     test_scenario::next_tx(scenario, user ); 
//     {
//       let data_val = test_scenario::take_shared<PresaleData>(scenario);
//       let data = &mut data_val;

//       assert!(auroraIco::get_is_whitelisted(data, user), 0);

//       test_scenario::return_shared(data_val);
//     };
//   }
//   fun assert_wallet_not_whitelisted(scenario: &mut Scenario, user: address) {
//     test_scenario::next_tx(scenario, user ); 
//     {
//       let data_val = test_scenario::take_shared<PresaleData>(scenario);
//       let data = &mut data_val;

//       assert!(auroraIco::get_is_whitelisted(data, user) == false, 0);

//       test_scenario::return_shared(data_val);
//     };
//   }

//   fun assert_user_bonus_balance(scenario: &mut Scenario, user: address, amount: u64) {
//     test_scenario::next_tx(scenario, user ); 
//     {
//       let userData = test_scenario::take_from_sender<UserData>(scenario);
//       let userDataMutable = &mut userData;

//       if(!HIDE_DEBUG_MESSAGES) {
//         std::debug::print(&333333);
//         std::debug::print(&auroraIco::get_calculated_bonus_reward(userDataMutable));
//       };
//       assert!(auroraIco::get_calculated_bonus_reward(userDataMutable) == amount, 0);


//       test_scenario::return_to_sender(scenario, userData);
//     };
//   }



//   // #[test]
//   // fun scen1_try_purchase_and_verify_invested_count() {
//   //   let user1 = @0x1;

//   //   let scenario_val = test_scenario::begin(user1);
//   //   let scenario = &mut scenario_val;
//   //   let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//   //   init_contract_for_resting(scenario, user1);

//   //   initialize_user_data(scenario, user1);
    
//   //   buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//   //   set_actual_amount_raised(scenario, user1, 14500000);
    
//   //   assert_user_sui_balance(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);
   
    
//   //   test_scenario::end(scenario_val);
//   //   clock::destroy_for_testing(clock_object);
//   // }

//   #[test]
//   fun scen0_try_purchase_and_verify_reward() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     buy_tokens(scenario, user1, 30000000);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_token_balance(scenario, user1, 30000000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }

//   #[test]
//   fun scen1_try_purchase_and_verify_reward() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//     set_actual_amount_raised(scenario, user1, 14500000 * TOKEN_UPSCALING_FACTOR);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_token_balance(scenario, user1, 99905000000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }
//   fun scen1x1_try_purchase_and_verify_reward() {
//     let user1 = @0x1;
//     let user2 = @0x2;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);
//     initialize_user_data(scenario, user2);

//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);
//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//     set_actual_amount_raised(scenario, user1, 14500000 * TOKEN_UPSCALING_FACTOR);

//     calculate_user_reward(scenario, user1);
//     calculate_user_reward(scenario, user2);
    
//     assert_user_token_balance(scenario, user1, 49952500000000);
//     assert_user_token_balance(scenario, user2, 49952500000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }
  
//   #[test]
//   fun scen1_try_purchase_and_verify_refunded_sui() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//     set_actual_amount_raised(scenario, user1, 14500000 * TOKEN_UPSCALING_FACTOR);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_sui_balance(scenario, user1, 900100000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }

//   #[test]
//   fun scen1_try_purchase_and_verify_bonus_reward() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     add_single_wallet_to_whitelist(scenario, user1, user1);

//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//     set_actual_amount_raised(scenario, user1, 14500000 * TOKEN_UPSCALING_FACTOR);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_bonus_balance(scenario, user1, 1130000000000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }

//   #[test]
//   fun scen2_try_purchase_and_verify_reward() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//     set_actual_amount_raised(scenario, user1, 2900000 * TOKEN_UPSCALING_FACTOR);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_token_balance(scenario, user1, 499960000000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }
  
//   #[test]
//   fun scen2_try_purchase_and_verify_refunded_sui() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//     set_actual_amount_raised(scenario, user1, 2900000 * TOKEN_UPSCALING_FACTOR);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_sui_balance(scenario, user1, 500040000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }

//   #[test]
//   fun scen2_try_purchase_and_verify_bonus_reward() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     add_single_wallet_to_whitelist(scenario, user1, user1);

//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//     set_actual_amount_raised(scenario, user1, 2900000 * TOKEN_UPSCALING_FACTOR);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_bonus_balance(scenario, user1, 1130000000000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }

//   #[test]
//   fun scen3_try_purchase_and_verify_reward() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//     set_actual_amount_raised(scenario, user1, 1450000 * TOKEN_UPSCALING_FACTOR);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_token_balance(scenario, user1, 999920000000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }
  
//   #[test]
//   fun scen3_try_purchase_and_verify_refunded_sui() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//     set_actual_amount_raised(scenario, user1, 1_450_000 * TOKEN_UPSCALING_FACTOR);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_sui_balance(scenario, user1, 80000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }

//   #[test]
//   fun scen3_try_purchase_and_verify_bonus_reward() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     add_single_wallet_to_whitelist(scenario, user1, user1);

//     buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

//     set_actual_amount_raised(scenario, user1, 1450000 * TOKEN_UPSCALING_FACTOR);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_bonus_balance(scenario, user1, 1130000000000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }

//   #[test]
//   fun scen4_try_purchase_and_verify_reward() {
//     let user1 = @0x1;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     buy_tokens(scenario, user1, 100_000_000);

//     calculate_user_reward(scenario, user1);
    
//     assert_user_token_balance(scenario, user1, 100000000000);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }
  
 
//   #[test]
//   #[expected_failure]
//   fun verify_psl04() {
//     let user1 = @0x1;
//     let user2 = @0x2;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     add_single_wallet_to_whitelist(scenario, user1, user2);
//     add_single_wallet_to_whitelist(scenario, user1, user2);
   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }
//   #[test]
//   fun verify_psl14() {
//     let user1 = @0x1;
//     let user2 = @0x2;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     add_single_wallet_to_whitelist(scenario, user1, user2);
//     remove_whitelist_entry(scenario, user1, user2);
//     // remove_whitelist_entry(scenario, user1, user2);

//     assert_wallet_not_whitelisted(scenario, user2);


   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }
//   #[test]
//   #[expected_failure]
//   fun verify_psl14_2() {
//     let user1 = @0x1;
//     let user2 = @0x2;

//     let scenario_val = test_scenario::begin(user1);
//     let scenario = &mut scenario_val;
//     let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
//     init_contract_for_resting(scenario, user1);

//     initialize_user_data(scenario, user1);

//     add_single_wallet_to_whitelist(scenario, user1, user2);
//     remove_whitelist_entry(scenario, user1, user2);
//     remove_whitelist_entry(scenario, user1, user2);



   
    
//     test_scenario::end(scenario_val);
//     clock::destroy_for_testing(clock_object);
//   }
  

  
// }


