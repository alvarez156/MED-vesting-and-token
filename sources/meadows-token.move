module meadow::meadow {
    use std::option;
    use sui::coin::{Self, TreasuryCap};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    const TOTAL_TOKEN_SUPPLY_MIST : u64 = 100_000_000 * 1_000_000_000;
    ///                                               ^ sui token decimals


    /// Name of the coin. By convention, this type has the same name as its parent module
    /// and has no fields. The full type of the coin defined by this module will be `COIN<MANAGED>`.
    struct MEADOW has drop {}


    /// Register the managed currency to acquire its `TreasuryCap`. Because
    /// this is a module initializer, it ensures the currency only gets
    /// registered once.
    fun init(witness: MEADOW, ctx: &mut TxContext) {
        // Get a treasury cap for the coin and give it to the transaction sender
        let (treasury_cap, metadata) = coin::create_currency<MEADOW>(witness, 9, b"MEADOW", b"", b"", option::none(), ctx);
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx))

    }

    /// Manager can mint new coins
    public entry fun mint_maximum_supply(
        treasury_cap: &mut TreasuryCap<MEADOW>, ctx: &mut TxContext
    ) {
        coin::mint_and_transfer(treasury_cap, TOTAL_TOKEN_SUPPLY_MIST, tx_context::sender(ctx), ctx);
    }

    public entry fun burn_treasury_cap(
        treasury_cap: TreasuryCap<MEADOW>
    ) {
        transfer::public_transfer(treasury_cap, @0x0000000000000000000000000000000000000000000000000000000000000000);
    }


}