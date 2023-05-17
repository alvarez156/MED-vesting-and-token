module meadow::private_sale {
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
    const EPresaleHardcapReached: u64 = 3;
    const EInsufficientPaymentSent: u64 = 4;
    const EUserDataAlreadyCreated : u64 = 5;

    const WITHDRAW_FUNDS_WALLET : address = @0x4b42d83ac73290815e32f883fcd7ec7f34e02bbdd80164bc98901fa3e53474bd;


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
        bonus: u64
    }

    struct FundsWithdrawn has copy, drop {
        wallet: address,
        amount: u64
    }

    // Scaling constants
    const TOKEN_UPSCALING_FACTOR: u64 = 1000000000;
    const TOKEN_UPSCALING_FACTOR_BIG_UINT: u256 = 1000000000;

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
        amountToBeRaisedUsd: u64,
        actualAmountRaisedUsd: u64,
        minimumContributionSui: u64,
        isPresaleActive: bool,
        whitelistedAddresses: vector<address>,
        contributors: vector<address>,
        bonusRewardPool: u64,
        bonusDepositPool: u64,
        testTotalSuiDeposited: u64,
    }


    struct UserData has key {
      id: UID,
      wallet: address,
      investedSui: u64,
      tokensBalance: u64,
      refundableSui: u64,
      calculatedTokensReward: u64,
      calculatedBonusReward: u64,
    }


    public entry fun get_sui_balance(
      user: &mut UserData,
    ): u64 {
      user.investedSui
    }

    public entry fun get_tokens_balance(
      user: &mut UserData,
    ): u64 {
      user.tokensBalance
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

    public entry fun get_amount_to_be_raised_usd(
      data: &mut PresaleData,
    ): u64 {
      data.amountToBeRaisedUsd
    }

    public entry fun get_actual_amount_raised_usd(
      data: &mut PresaleData,
    ): u64 {
      data.actualAmountRaisedUsd
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
          suiPerToken: 1000000, // for testing we're using a scale of 1,000,000,000
          totalTokensForSale: 1450000000 * TOKEN_UPSCALING_FACTOR,
          totalSuiDeposited: balance::zero(),
          amountToBeRaisedUsd: 1450000,
          actualAmountRaisedUsd: 0,
          minimumContributionSui: 1,
          isPresaleActive: true,
          whitelistedAddresses: vec::empty(),
          contributors: vec::empty(),
          bonusRewardPool: 1130000 * TOKEN_UPSCALING_FACTOR,
          bonusDepositPool: 0, // 0 tokens initially
          testTotalSuiDeposited: 0,
        })
    }

    public entry fun add_single_whitelist_entry(
      _: &ICOOperatorCapability,
      data: &mut PresaleData,
      address: address,
    ) {
      vec::push_back(&mut data.whitelistedAddresses, address);
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
      assert!(data.isPresaleActive == true, ECannotEndAlreadyEndedPresale);

      data.isPresaleActive = false;
    }

    public entry fun change_ico_timeframes(
      _: &ICOOperatorCapability,
      data: &mut PresaleData,
      icoStartTimestamp: u64,
      icoEndTimestamp: u64,
    ) {
      
      data.icoStartTimestamp = icoStartTimestamp;
      data.icoEndTimestamp = icoEndTimestamp;
    }

    public entry fun create_user_data(
      data: &mut PresaleData,
      wallet: address,
      ctx: &mut TxContext,
    ) {

      assert!(vec::contains(&data.whitelistedAddresses, &tx_context::sender(ctx)) == false, EUserDataAlreadyCreated);
      vec::push_back(&mut data.contributors, tx_context::sender(ctx));

      transfer::transfer(UserData {
        id: object::new(ctx),
        wallet: wallet,
        investedSui: 0,
        tokensBalance: 0,
        refundableSui: 0,
        calculatedTokensReward: 0,
        calculatedBonusReward: 0,
      }, tx_context::sender(ctx));
    }

    public entry fun purchase_tokens(
      data: &mut PresaleData,
      user: &mut UserData,
      payment: &mut Coin<SUI>,
      amount: u64,
      clock: &Clock,
      ctx: &mut TxContext,
    ) {

      let currentTimestamp = clock::timestamp_ms(clock);

      // Make the necessary checks
      assert!(coin::value(payment) > data.minimumContributionSui, EInsufficientPaymentSent);
      assert!(currentTimestamp >= data.icoStartTimestamp, EPresaleNotStarted);
      assert!(currentTimestamp <= data.icoEndTimestamp, EPresaleEnded);

      let sui_balance = coin::balance_mut(payment);
      let payment = balance::split(sui_balance, amount);

      user.investedSui = user.investedSui + balance::value(&payment);

      let purchaseUsdValue = balance::value(&payment) * data.suiPerToken;

      event::emit(SuiContributionRecieved { wallet: tx_context::sender(ctx), amount: balance::value(&payment) });

      // Transfer the SUI to the contract
      balance::join(&mut data.totalSuiDeposited, payment);

      data.actualAmountRaisedUsd = data.actualAmountRaisedUsd + purchaseUsdValue / TOKEN_UPSCALING_FACTOR * 2;

    }

    public entry fun calculate_elligible_rewards(
      data: &mut PresaleData,
      user: &mut UserData,
      ctx: &mut TxContext,
    ) {

      //TODO: Only calculate after presale has ended


      let reward = calculate_reward(
        user.investedSui,
        data.totalTokensForSale,
        data.actualAmountRaisedUsd,
      );

      let refundableTokens =
        calculate_refundable_reward(
          user.investedSui,
          data.suiPerToken,
          data.totalTokensForSale,
          data.actualAmountRaisedUsd,
        );
      

      let isUserWhitelisted = get_is_whitelisted(data, tx_context::sender(ctx));

      if(isUserWhitelisted) {

        // For testing, use line 353 instead of 354
        // For devnet deployment, use line 354 instead of 353

        user.calculatedBonusReward = calculate_bonus_reward(
          user.investedSui,
          data.bonusRewardPool,
          data.testTotalSuiDeposited
          // balance::value(&data.totalSuiDeposited),
        );

      };

      // Consume all the user's invested sui
      user.investedSui = 0;

      // Transfer the tokens to the user
      user.tokensBalance = user.tokensBalance + reward;

      // Transfer the refundable tokens to the user
      user.refundableSui = user.refundableSui + refundableTokens;

      // Set the values in the user's struct
      user.calculatedTokensReward = reward;

      event::emit(RewardsCalculated { wallet: tx_context::sender(ctx), tokens: reward, bonus: user.calculatedBonusReward });
    }

    fun calculate_reward(
      suiIn: u64,
      totalTokensForSale: u64,
      actualAmountRaisedUsd: u64,
    ): u64 {
      let shareFromInvestmentPool = suiIn * 10000 / actualAmountRaisedUsd;
      let claimableTokens = shareFromInvestmentPool * (totalTokensForSale / TOKEN_UPSCALING_FACTOR);
      let claimableTokensDownscaled = claimableTokens / 10000;
      claimableTokensDownscaled
    }


    fun calculate_refundable_reward(
      suiIn: u64,
      suiPerToken: u64,
      totalTokensForSale: u64,
      actualAmountRaisedUsd: u64,
    ): u64 {

      let shareFromInvestmentPool = suiIn * 10000 / actualAmountRaisedUsd;
      let claimableTokens = shareFromInvestmentPool * (totalTokensForSale / TOKEN_UPSCALING_FACTOR);
      let claimableTokensDownscaled = claimableTokens / 10000 / TOKEN_UPSCALING_FACTOR;
      let tokensValueInSui = (claimableTokensDownscaled * suiPerToken);
      let refundableTokens = (suiIn - tokensValueInSui);
      refundableTokens
    }

    fun calculate_bonus_reward(
      suiIn: u64,
      bonusRewardPoolValue: u64,
      bonusDepositPoolValue: u64,
    ): u64 {

      let shareFromRewardPool = suiIn * 10000 / bonusDepositPoolValue;
      let claimableTokens = shareFromRewardPool * bonusRewardPoolValue;
      let claimableTokensDownscaled = claimableTokens / 10000;
      claimableTokensDownscaled

    }

    public entry fun withdraw_funds(
      _: &ICOOperatorCapability,
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
        data.actualAmountRaisedUsd = amount;
    }

    #[test_only]
    public entry fun test_purchase_tokens(
      data: &mut PresaleData,
      user: &mut UserData,
      amount: u64,
    ) {

      user.investedSui = user.investedSui + amount;

      let purchaseUsdValue = amount * data.suiPerToken / TOKEN_UPSCALING_FACTOR * 2;

      // Transfer the SUI to the contract
      data.testTotalSuiDeposited = data.testTotalSuiDeposited + amount;
      data.actualAmountRaisedUsd = data.actualAmountRaisedUsd + purchaseUsdValue;

    }

}

#[test_only]
module meadow::private_sale_test {

  use sui::test_scenario::{Self, Scenario};
  // use sui::coin::{Self, Coin};
  // use sui::balance::{Self, Balance};
  // use sui::sui::SUI;
  use meadow::private_sale::{Self, PresaleData, UserData, ICOOperatorCapability };
  use sui::clock::{Self};
  // use std::debug;
  // use std::vector as vec;
  // use sui::transfer;

  const TOKEN_UPSCALING_FACTOR: u64 = 1000000000;
  const HIDE_DEBUG_MESSAGES: bool = false;

  fun initialize_user_data(scenario: &mut Scenario, user: address) {
    // User1 initializes their user object
    test_scenario::next_tx(scenario, user);
    {
      let data_val = test_scenario::take_shared<PresaleData>(scenario);
      let data = &mut data_val;
      let ctx = test_scenario::ctx(scenario);

      // Attempt to create user object firstf

      private_sale::create_user_data(data, user, ctx);

      test_scenario::return_shared(data_val);
    };
  }

  fun add_single_wallet_to_whitelist(scenario: &mut Scenario, user: address, wallet: address) {
   // Attempt to add a single user to the whitelist
  test_scenario::next_tx(scenario, user);
  {

    let data_val = test_scenario::take_shared<PresaleData>(scenario);
    let data = &mut data_val;


    let presale_owner_cap_val = test_scenario::take_from_sender<ICOOperatorCapability>(scenario);
    let presale_owner_cap = &mut presale_owner_cap_val;

    private_sale::add_single_whitelist_entry(
      presale_owner_cap,
      data,
      wallet,
    );

    test_scenario::return_to_sender(scenario, presale_owner_cap_val);
    test_scenario::return_shared(data_val);
  };
  }

  fun buy_tokens(scenario: &mut Scenario, user: address, amount: u64) {
    test_scenario::next_tx(scenario, user);
    {
      let data_val = test_scenario::take_shared<PresaleData>(scenario);
      let data = &mut data_val;
      let userData = test_scenario::take_from_sender<UserData>(scenario);
      let userDataMutable = &mut userData;

      // Purchase tokens

      private_sale::test_purchase_tokens(
        data, 
        userDataMutable, 
        amount,
      );

      // assert!(balance::value(&settings.suiBalance) == 10, 0);

      test_scenario::return_to_sender(scenario, userData);
      test_scenario::return_shared(data_val);
    };
  }

  fun set_actual_amount_raised(scenario: &mut Scenario, user: address, amount: u64) {
    test_scenario::next_tx(scenario, user);
    {
      let data_val = test_scenario::take_shared<PresaleData>(scenario);
      let data = &mut data_val;

      private_sale::set_actual_amount_raised(
        data,
        amount,
      );

      let amountRaised = private_sale::get_actual_amount_raised_usd(data);
      assert!(amountRaised == amount, 0);

      test_scenario::return_shared(data_val);
    };
  }

  fun calculate_user_reward(scenario: &mut Scenario, user: address) {
    test_scenario::next_tx(scenario, user);
    {
      let data_val = test_scenario::take_shared<PresaleData>(scenario);
      let data = &mut data_val;
      let userData = test_scenario::take_from_sender<UserData>(scenario);
      let userDataMutable = &mut userData;

      // Purchase tokens

      let ctx = test_scenario::ctx(scenario);
      private_sale::calculate_elligible_rewards(
        data, 
        userDataMutable, 
        ctx,
      );

      // assert!(balance::value(&settings.suiBalance) == 10, 0);

      test_scenario::return_to_sender(scenario, userData);
      test_scenario::return_shared(data_val);
    };
  }

  fun init_contract_for_resting(scenario: &mut Scenario, user: address) {
    test_scenario::next_tx(scenario, user);
    {
      private_sale::init_for_testing(test_scenario::ctx(scenario));
    };
  }

  fun assert_user_sui_balance(scenario: &mut Scenario, user: address, amount: u64) {
    test_scenario::next_tx(scenario, user ); 
    {
      let userData = test_scenario::take_from_sender<UserData>(scenario);
      let userDataMutable = &mut userData;

      if(!HIDE_DEBUG_MESSAGES) {
        std::debug::print(&111111);
        std::debug::print(&private_sale::get_refundable_sui(userDataMutable));
      };
      

      assert!(private_sale::get_refundable_sui(userDataMutable) == amount, 0);


      test_scenario::return_to_sender(scenario, userData);
    };
  }

  fun assert_user_token_balance(scenario: &mut Scenario, user: address, amount: u64) {
    test_scenario::next_tx(scenario, user ); 
    {
      let userData = test_scenario::take_from_sender<UserData>(scenario);
      let userDataMutable = &mut userData;

      if(!HIDE_DEBUG_MESSAGES) {
        std::debug::print(&222222);
        std::debug::print(&private_sale::get_calculated_tokens_reward(userDataMutable));
      };
      assert!(private_sale::get_calculated_tokens_reward(userDataMutable) == amount, 0);


      test_scenario::return_to_sender(scenario, userData);
    };
  }

  fun assert_user_bonus_balance(scenario: &mut Scenario, user: address, amount: u64) {
    test_scenario::next_tx(scenario, user ); 
    {
      let userData = test_scenario::take_from_sender<UserData>(scenario);
      let userDataMutable = &mut userData;

      if(!HIDE_DEBUG_MESSAGES) {
        std::debug::print(&333333);
        std::debug::print(&private_sale::get_calculated_bonus_reward(userDataMutable));
      };
      assert!(private_sale::get_calculated_bonus_reward(userDataMutable) == amount, 0);


      test_scenario::return_to_sender(scenario, userData);
    };
  }



  // #[test]
  // fun scen1_try_purchase_and_verify_invested_count() {
  //   let user1 = @0x1;

  //   let scenario_val = test_scenario::begin(user1);
  //   let scenario = &mut scenario_val;
  //   let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
  //   init_contract_for_resting(scenario, user1);

  //   initialize_user_data(scenario, user1);
    
  //   buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

  //   set_actual_amount_raised(scenario, user1, 14500000);
    
  //   assert_user_sui_balance(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);
   
    
  //   test_scenario::end(scenario_val);
  //   clock::destroy_for_testing(clock_object);
  // }

  #[test]
  fun scen1_try_purchase_and_verify_reward() {
    let user1 = @0x1;

    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;
    let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
    init_contract_for_resting(scenario, user1);

    initialize_user_data(scenario, user1);

    buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

    set_actual_amount_raised(scenario, user1, 14500000);

    calculate_user_reward(scenario, user1);
    
    assert_user_token_balance(scenario, user1, 99999999940000);
   
    
    test_scenario::end(scenario_val);
    clock::destroy_for_testing(clock_object);
  }
  
  #[test]
  fun scen1_try_purchase_and_verify_refunded_sui() {
    let user1 = @0x1;

    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;
    let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
    init_contract_for_resting(scenario, user1);

    initialize_user_data(scenario, user1);

    buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

    set_actual_amount_raised(scenario, user1, 14500000);

    calculate_user_reward(scenario, user1);
    
    assert_user_sui_balance(scenario, user1, 900001000000);
   
    
    test_scenario::end(scenario_val);
    clock::destroy_for_testing(clock_object);
  }

  #[test]
  fun scen1_try_purchase_and_verify_bonus_reward() {
    let user1 = @0x1;

    let scenario_val = test_scenario::begin(user1);
    let scenario = &mut scenario_val;
    let clock_object = clock::create_for_testing(test_scenario::ctx(scenario));

   
    init_contract_for_resting(scenario, user1);

    initialize_user_data(scenario, user1);

    add_single_wallet_to_whitelist(scenario, user1, user1);

    buy_tokens(scenario, user1, 1000 * TOKEN_UPSCALING_FACTOR);

    set_actual_amount_raised(scenario, user1, 14500000);

    calculate_user_reward(scenario, user1);
    
    assert_user_bonus_balance(scenario, user1, 1130000000000000);
   
    
    test_scenario::end(scenario_val);
    clock::destroy_for_testing(clock_object);
  }


  
}


