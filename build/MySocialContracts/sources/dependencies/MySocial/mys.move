// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Coin<MYS> is the token used to pay for gas in Mys.
/// It has 9 decimals, and the smallest unit (10^-9) is called "mist".
module mys::mys;

use mys::balance::Balance;
use mys::coin;

const EAlreadyMinted: u64 = 0;
/// Sender is not @0x0 the system address.
const ENotSystemAddress: u64 = 1;

#[allow(unused_const)]
/// The amount of Mist per Mys token based on the fact that mist is
/// 10^-9 of a Mys token
const MIST_PER_MYS: u64 = 1_000_000_000;

#[allow(unused_const)]
/// The total supply of Mys denominated in whole Mys tokens (10 Billion)
const TOTAL_SUPPLY_MYS: u64 = 10_000_000_000;

/// The total supply of Mys denominated in Mist (10 Billion * 10^9)
const TOTAL_SUPPLY_MIST: u64 = 10_000_000_000_000_000_000;

/// Name of the coin
public struct MYS has drop {}

#[allow(unused_function)]
/// Register the `MYS` Coin to acquire its `Supply`.
/// This should be called only once during genesis creation.
fun new(ctx: &mut TxContext): Balance<MYS> {
    assert!(ctx.sender() == @0x0, ENotSystemAddress);
    assert!(ctx.epoch() == 0, EAlreadyMinted);

    let (treasury, metadata) = coin::create_currency(
        MYS {},
        9,
        b"MYS",
        b"Mys",
        // TODO: add appropriate description and logo url
        b"",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    let mut supply = treasury.treasury_into_supply();
    let total_mys = supply.increase_supply(TOTAL_SUPPLY_MIST);
    supply.destroy_supply();
    total_mys
}

public entry fun transfer(c: coin::Coin<MYS>, recipient: address) {
    transfer::public_transfer(c, recipient)
}
