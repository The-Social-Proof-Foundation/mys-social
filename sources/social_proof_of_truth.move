// Copyright (c) The Social Proof Foundation, LLC.
// SPDX-License-Identifier: Apache-2.0

/// Social Proof of Truth (SPoT)
/// Prediction-like truth market on posts with split entry: AMM buy (beta) + escrow (1-beta),
/// oracle/DAO resolution, and pro-rata payouts from escrow. Integrates with SPT post pools.

#[allow(duplicate_alias, unused_use, unused_const, unused_variable, lint(self_transfer, share_owned))]
module social_contracts::social_proof_of_truth {
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use std::vector;

    use mys::{
        object::{Self, UID},
        tx_context::{Self, TxContext},
        transfer,
        event,
        coin::{Self, Coin},
        balance::{Self, Balance},
        table::{Self, Table},
    };
    use mys::mys::MYS;

    use social_contracts::post::{Self, Post};
    use social_contracts::platform::{Self, Platform};
    use social_contracts::block_list::BlockListRegistry;
    use social_contracts::upgrade::{Self, UpgradeAdminCap};

    /// Errors
    const EDisabled: u64 = 1;
    const EInvalidAmount: u64 = 2;
    const EAlreadyResolved: u64 = 3;
    const ETooEarly: u64 = 4;
    const ETooClose: u64 = 5;
    const EWrongStatus: u64 = 6;
    const ENotOracle: u64 = 7;
    const ENoBets: u64 = 8;
    const EAutoInitOnlyWhenMissing: u64 = 9;
    const EThrottle: u64 = 10;

    /// Status
    const STATUS_OPEN: u8 = 1;
    const STATUS_DAO_REQUIRED: u8 = 2;
    const STATUS_RESOLVED: u8 = 3;
    const STATUS_REFUNDABLE: u8 = 4;

    /// Outcomes
    const OUTCOME_YES: u8 = 1;
    const OUTCOME_NO: u8 = 2;
    const OUTCOME_DRAW: u8 = 3;
    const OUTCOME_UNAPPLICABLE: u8 = 4;

    /// Config defaults
    const DEFAULT_AMM_SPLIT_BPS: u64 = 3000; // 30%
    const DEFAULT_CONFIDENCE_THRESHOLD_BPS: u64 = 7000; // 70%
    const DEFAULT_ENABLE: bool = true;
    const DEFAULT_RESOLUTION_WINDOW_EPOCHS: u64 = 72; // depends on epoch length
    const DEFAULT_MAX_RESOLUTION_WINDOW_EPOCHS: u64 = 144;
    const DEFAULT_PAYOUT_DELAY_EPOCHS: u64 = 0;
    const DEFAULT_FEE_BPS: u64 = 100; // 1%
    const DEFAULT_FEE_SPLIT_PLATFORM_BPS: u64 = 5000; // 50% of fee to platform

    /// Admin capability for SPoT
    public struct SpotAdminCap has key, store { id: UID }

    /// Global configuration for SPoT
    public struct SpotConfig has key {
        id: UID,
        enable_flag: bool,
        amm_split_bps: u64,
        confidence_threshold_bps: u64,
        resolution_window_epochs: u64,
        max_resolution_window_epochs: u64,
        payout_delay_epochs: u64,
        fee_bps: u64,
        fee_split_bps_platform: u64,
        platform_treasury: address,
        chain_treasury: address,
        oracle_address: address,
        max_single_bet: u64,
        version: u64,
    }

    /// A single bet
    public struct SpotBet has store, copy, drop {
        user: address,
        is_yes: bool,
        escrow_amount: u64,
        amm_amount: u64,
        timestamp: u64,
    }

    /// SPoT record per post
    public struct SpotRecord has key, store {
        id: UID,
        post_id: address,
        created_epoch: u64,
        status: u8,
        outcome: Option<u8>,
        amm_split_bps_used: u64,
        escrow: Balance<MYS>,
        total_yes_escrow: u64,
        total_no_escrow: u64,
        bets: vector<SpotBet>,
        last_resolution_epoch: u64,
        version: u64,
    }

    /// Events
    public struct SpotBetPlacedEvent has copy, drop {
        post_id: address,
        user: address,
        is_yes: bool,
        escrow_amount: u64,
        amm_amount: u64,
    }

    public struct SpotResolvedEvent has copy, drop {
        post_id: address,
        outcome: u8,
        total_escrow: u64,
        fee_taken: u64,
    }

    public struct SpotDaoRequiredEvent has copy, drop {
        post_id: address,
        confidence_bps: u64,
    }

    public struct SpotPayoutEvent has copy, drop {
        post_id: address,
        user: address,
        amount: u64,
    }

    public struct SpotRefundEvent has copy, drop {
        post_id: address,
        user: address,
        amount: u64,
    }

    // Public getters for testing/inspection
    public fun get_status(rec: &SpotRecord): u8 { rec.status }
    public fun get_total_yes_escrow(rec: &SpotRecord): u64 { rec.total_yes_escrow }
    public fun get_total_no_escrow(rec: &SpotRecord): u64 { rec.total_no_escrow }
    public fun get_bets_len(rec: &SpotRecord): u64 { vector::length(&rec.bets) }

    // Bootstrap
    public(package) fun bootstrap_init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);
        transfer::share_object(SpotConfig {
            id: object::new(ctx),
            enable_flag: DEFAULT_ENABLE,
            amm_split_bps: DEFAULT_AMM_SPLIT_BPS,
            confidence_threshold_bps: DEFAULT_CONFIDENCE_THRESHOLD_BPS,
            resolution_window_epochs: DEFAULT_RESOLUTION_WINDOW_EPOCHS,
            max_resolution_window_epochs: DEFAULT_MAX_RESOLUTION_WINDOW_EPOCHS,
            payout_delay_epochs: DEFAULT_PAYOUT_DELAY_EPOCHS,
            fee_bps: DEFAULT_FEE_BPS,
            fee_split_bps_platform: DEFAULT_FEE_SPLIT_PLATFORM_BPS,
            platform_treasury: admin,
            chain_treasury: admin,
            oracle_address: admin,
            max_single_bet: 0,
            version: upgrade::current_version(),
        });
        transfer::public_transfer(SpotAdminCap { id: object::new(ctx) }, admin);
    }

    /// Update SPoT configuration (admin only)
    public entry fun update_spot_config(
        _: &SpotAdminCap,
        config: &mut SpotConfig,
        enable_flag: bool,
        amm_split_bps: u64,
        confidence_threshold_bps: u64,
        resolution_window_epochs: u64,
        max_resolution_window_epochs: u64,
        payout_delay_epochs: u64,
        fee_bps: u64,
        fee_split_bps_platform: u64,
        platform_treasury: address,
        chain_treasury: address,
        oracle_address: address,
        max_single_bet: u64,
        _ctx: &mut TxContext
    ) {
        // Basic bounds
        assert!(amm_split_bps <= 10000, EInvalidAmount);
        assert!(confidence_threshold_bps <= 10000, EInvalidAmount);
        // windows may be zero in tests to resolve immediately

        config.enable_flag = enable_flag;
        config.amm_split_bps = amm_split_bps;
        config.confidence_threshold_bps = confidence_threshold_bps;
        config.resolution_window_epochs = resolution_window_epochs;
        config.max_resolution_window_epochs = max_resolution_window_epochs;
        config.payout_delay_epochs = payout_delay_epochs;
        config.fee_bps = fee_bps;
        config.fee_split_bps_platform = fee_split_bps_platform;
        config.platform_treasury = platform_treasury;
        config.chain_treasury = chain_treasury;
        config.oracle_address = oracle_address;
        config.max_single_bet = max_single_bet;
    }

    // Utility
    fun split_amount(amount: u64, bps: u64): (u64, u64) {
        let amm = (amount * bps) / 10000;
        let escrow = amount - amm;
        (amm, escrow)
    }

    // Create a SPoT record for a post
    public entry fun create_spot_record_for_post(
        config: &SpotConfig,
        post: &Post,
        ctx: &mut TxContext
    ) {
        assert!(config.enable_flag, EDisabled);
        let record = SpotRecord {
            id: object::new(ctx),
            post_id: post::get_id_address(post),
            created_epoch: tx_context::epoch(ctx),
            status: STATUS_OPEN,
            outcome: option::none(),
            amm_split_bps_used: config.amm_split_bps,
            escrow: balance::zero(),
            total_yes_escrow: 0,
            total_no_escrow: 0,
            bets: vector::empty<SpotBet>(),
            last_resolution_epoch: 0,
            version: upgrade::current_version(),
        };
        transfer::share_object(record);
    }

    /// Place bet when pool already exists
    public entry fun place_spot_bet_with_pool(
        spot_config: &SpotConfig,
        spt_registry: &social_contracts::social_proof_tokens::TokenRegistry,
        spt_config: &social_contracts::social_proof_tokens::SocialProofTokensConfig,
        record: &mut SpotRecord,
        post: &Post,
        pool: &mut social_contracts::social_proof_tokens::TokenPool,
        platform: &mut Platform,
        block_list_registry: &BlockListRegistry,
        mut payment: Coin<MYS>,
        is_yes: bool,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(spot_config.enable_flag, EDisabled);
        assert!(amount > 0, EInvalidAmount);
        if (spot_config.max_single_bet > 0) { assert!(amount <= spot_config.max_single_bet, EInvalidAmount); };

        // Split entry between AMM and escrow
        let (amm_amount, escrow_amount) = split_amount(amount, spot_config.amm_split_bps);
        assert!(coin::value(&payment) >= amount, EInvalidAmount);

        // AMM buy on SPT pool for AMM portion
        if (amm_amount > 0) {
            let amm_coin = coin::split(&mut payment, amm_amount, ctx);
            social_contracts::social_proof_tokens::buy_tokens(
                spt_registry,
                pool,
                spt_config,
                block_list_registry,
                platform,
                amm_coin,
                1, // buy at least 1 token unit equivalent; curve handles pricing
                ctx,
            );
        };

        // Escrow the remainder
        if (escrow_amount > 0) {
            let esc = coin::split(&mut payment, escrow_amount, ctx);
            balance::join(&mut record.escrow, coin::into_balance(esc));
            if (is_yes) { record.total_yes_escrow = record.total_yes_escrow + escrow_amount; }
            else { record.total_no_escrow = record.total_no_escrow + escrow_amount; };
        };

        // Refund any excess
        if (coin::value(&payment) > 0) { transfer::public_transfer(payment, tx_context::sender(ctx)); }
        else { coin::destroy_zero(payment); };

        // Record bet
        vector::push_back(&mut record.bets, SpotBet {
            user: tx_context::sender(ctx),
            is_yes,
            escrow_amount,
            amm_amount,
            timestamp: tx_context::epoch(ctx),
        });

        event::emit(SpotBetPlacedEvent {
            post_id: post::get_id_address(post),
            user: tx_context::sender(ctx),
            is_yes,
            escrow_amount,
            amm_amount,
        });
    }

    /// Place bet and auto-initialize pool if missing (guarded in SPT)
    public entry fun place_spot_bet_auto_init(
        spot_config: &SpotConfig,
        spt_registry: &mut social_contracts::social_proof_tokens::TokenRegistry,
        spt_config: &mut social_contracts::social_proof_tokens::SocialProofTokensConfig,
        record: &mut SpotRecord,
        post: &Post,
        platform: &mut Platform,
        block_list_registry: &BlockListRegistry,
        payment: Coin<MYS>,
        is_yes: bool,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(spot_config.enable_flag, EDisabled);
        // Ensure there is no existing pool; create if allowed
        let post_id = post::get_id_address(post);
        let exists = social_contracts::social_proof_tokens::token_exists(spt_registry, post_id);
        assert!(!exists, EAutoInitOnlyWhenMissing);

        let mut maybe_pool = social_contracts::social_proof_tokens::ensure_post_token_pool(
            spt_registry,
            spt_config,
            post,
            ctx,
        );
        assert!(option::is_some(&maybe_pool), EThrottle);
        let mut pool = option::extract(&mut maybe_pool);

        // Place bet using the newly created pool
        place_spot_bet_with_pool(
            spot_config,
            spt_registry,
            spt_config,
            record,
            post,
            &mut pool,
            platform,
            block_list_registry,
            payment,
            is_yes,
            amount,
            ctx,
        );

        // Share pool after in-tx operations
        transfer::public_share_object(pool);
        // Consume the now-empty option to satisfy drop constraints
        option::destroy_none(maybe_pool);
    }

    /// Oracle resolution (YES/NO, or too close → DAO_REQUIRED)
    public entry fun oracle_resolve(
        spot_config: &SpotConfig,
        record: &mut SpotRecord,
        post: &Post,
        outcome_yes: bool,
        confidence_bps: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == spot_config.oracle_address, ENotOracle);
        assert!(record.status == STATUS_OPEN, EWrongStatus);
        // Enforce resolution window
        let now = tx_context::epoch(ctx);
        assert!(now >= record.created_epoch + spot_config.resolution_window_epochs, ETooEarly);

        if (confidence_bps < spot_config.confidence_threshold_bps) {
            record.status = STATUS_DAO_REQUIRED;
            event::emit(SpotDaoRequiredEvent { post_id: post::get_id_address(post), confidence_bps });
            return
        };

        // Resolve outcome
        let outcome = if (outcome_yes) { OUTCOME_YES } else { OUTCOME_NO };
        finalize_resolution_and_payout(spot_config, record, post, outcome, ctx);
    }

    /// DAO finalization (YES/NO/DRAW/UNAPPLICABLE)
    public entry fun finalize_via_dao(
        spot_config: &SpotConfig,
        record: &mut SpotRecord,
        post: &Post,
        outcome: u8,
        ctx: &mut TxContext
    ) {
        // Allow when DAO_REQUIRED or still OPEN (off-chain DAO direct)
        assert!(record.status == STATUS_DAO_REQUIRED || record.status == STATUS_OPEN, EWrongStatus);
        finalize_resolution_and_payout(spot_config, record, post, outcome, ctx);
    }

    /// Refund all escrow if unresolved beyond max window
    public entry fun refund_unresolved(
        spot_config: &SpotConfig,
        record: &mut SpotRecord,
        post: &Post,
        ctx: &mut TxContext
    ) {
        let now = tx_context::epoch(ctx);
        assert!(now >= record.created_epoch + spot_config.max_resolution_window_epochs, ETooEarly);
        assert!(record.status == STATUS_OPEN || record.status == STATUS_DAO_REQUIRED, EWrongStatus);
        assert!(vector::length(&record.bets) > 0, ENoBets);

        // Iterate all bets and refund escrow
        let mut i = 0;
        let len = vector::length(&record.bets);
        while (i < len) {
            let bet = vector::borrow(&record.bets, i);
            if (bet.escrow_amount > 0) {
                let c = coin::from_balance(balance::split(&mut record.escrow, bet.escrow_amount), ctx);
                transfer::public_transfer(c, bet.user);
                event::emit(SpotRefundEvent { post_id: record.post_id, user: bet.user, amount: bet.escrow_amount });
            };
            i = i + 1;
        };
        record.status = STATUS_REFUNDABLE;
        record.outcome = option::none();
        record.last_resolution_epoch = now;
        // Any dust stays in escrow balance if math rounding occurred
    }

    // Internal: finalize with payouts and fees
    fun finalize_resolution_and_payout(
        spot_config: &SpotConfig,
        record: &mut SpotRecord,
        post: &Post,
        outcome: u8,
        ctx: &mut TxContext
    ) {
        assert!(record.status == STATUS_OPEN || record.status == STATUS_DAO_REQUIRED, EWrongStatus);
        assert!(vector::length(&record.bets) > 0, ENoBets);

        // Winner side total
        let total_yes = record.total_yes_escrow;
        let total_no = record.total_no_escrow;
        let total_escrow = total_yes + total_no;

        // Handle DRAW/UNAPPLICABLE: refund all escrow
        if (outcome == OUTCOME_DRAW || outcome == OUTCOME_UNAPPLICABLE) {
            let mut i = 0; let len = vector::length(&record.bets);
            while (i < len) {
                let bet = vector::borrow(&record.bets, i);
                if (bet.escrow_amount > 0) {
                    let c = coin::from_balance(balance::split(&mut record.escrow, bet.escrow_amount), ctx);
                    transfer::public_transfer(c, bet.user);
                    event::emit(SpotRefundEvent { post_id: record.post_id, user: bet.user, amount: bet.escrow_amount });
                };
                i = i + 1;
            };
            record.status = STATUS_RESOLVED;
            record.outcome = option::some(outcome);
            record.last_resolution_epoch = tx_context::epoch(ctx);
            event::emit(SpotResolvedEvent { post_id: post::get_id_address(post), outcome, total_escrow, fee_taken: 0 });
            return
        };

        let (winning_total, is_yes_winning) = if (outcome == OUTCOME_YES) { (total_yes, true) } else { (total_no, false) };

        // Fees on payouts (apply to total escrow)
        let mut fee = 0;
        if (spot_config.fee_bps > 0) { fee = (total_escrow * spot_config.fee_bps) / 10000; };
        let distributable = total_escrow - fee;

        // Split fee 50/50 (configurable)
        if (fee > 0) {
            let platform_part = (fee * spot_config.fee_split_bps_platform) / 10000;
            let chain_part = fee - platform_part;
            let mut fee_coin = coin::from_balance(balance::split(&mut record.escrow, fee), ctx);
            let platform_coin = coin::split(&mut fee_coin, platform_part, ctx);
            transfer::public_transfer(platform_coin, spot_config.platform_treasury);
            transfer::public_transfer(fee_coin, spot_config.chain_treasury);
        };

        // Distribute to winners pro-rata of total escrow
        let mut i = 0; let len = vector::length(&record.bets);
        while (i < len) {
            let bet = vector::borrow(&record.bets, i);
            let winner = (bet.is_yes && is_yes_winning) || (!bet.is_yes && !is_yes_winning);
            if (winner && winning_total > 0 && bet.escrow_amount > 0) {
                let payout = (((bet.escrow_amount as u128) * (distributable as u128)) / (winning_total as u128)) as u64;
                if (payout > 0) {
                    let c = coin::from_balance(balance::split(&mut record.escrow, payout), ctx);
                    transfer::public_transfer(c, bet.user);
                    event::emit(SpotPayoutEvent { post_id: record.post_id, user: bet.user, amount: payout });
                };
            };
            i = i + 1;
        };

        record.status = STATUS_RESOLVED;
        record.outcome = option::some(outcome);
        record.last_resolution_epoch = tx_context::epoch(ctx);
        event::emit(SpotResolvedEvent { post_id: post::get_id_address(post), outcome, total_escrow, fee_taken: fee });
    }
}
