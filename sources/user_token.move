// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// User token implementation for MySocial platform. This module provides functionality
/// for admin-controlled user token creation without allowing users to control the supply.
/// It includes fee distribution mechanisms for swaps and trading.
module social_contracts::user_token {
    use std::ascii;
    use std::string;
    use std::vector;
    use std::option::{Self, Option};
    use mys::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use mys::object::{Self, UID};
    use mys::transfer;
    use mys::tx_context::{Self, TxContext};
    use mys::url::{Self, Url};
    use mys::balance::{Self, Balance};
    use mys::event;
    
    // === Errors ===
    /// Operation can only be performed by the platform admin
    const ENotAuthorized: u64 = 0;
    /// Invalid commission fee percentage
    const EInvalidCommission: u64 = 1;
    /// Invalid fee split configuration
    const EInvalidFeeSplit: u64 = 2;
    /// The token is not registered
    const ETokenNotRegistered: u64 = 3;
    /// Swap failed - insufficient balance or liquidity
    const ESwapFailed: u64 = 4;
    /// The user already has a token
    const ETokenAlreadyExists: u64 = 5;
    /// Invalid token configuration
    const EInvalidConfig: u64 = 6;

    // === Constants ===
    // Maximum commission fee percentage (in basis points, 10000 = 100%)
    const MAX_COMMISSION_BPS: u64 = 3000; // 30%
    // Maximum platform fee percentage of the commission
    const MAX_PLATFORM_SPLIT_BPS: u64 = 5000; // 50% of commission
    // Default commission fee if not specified (in basis points)
    const DEFAULT_COMMISSION_BPS: u64 = 1000; // 10%
    // Default creator/platform split (in basis points: 8000 = 80% to creator, 20% to platform)
    const DEFAULT_CREATOR_SPLIT_BPS: u64 = 8000;

    // === Structs ===
    
    /// Admin capability for the MySocial platform
    /// Only the holder of this capability can create user tokens
    public struct AdminCap has key, store {
        id: UID,
    }
    
    /// Registry to track all user tokens on the platform
    public struct TokenRegistry has key {
        id: UID,
        // Maps user address to their token type ID
        tokens: vector<UserTokenInfo>,
    }
    
    /// Information about a user token
    public struct UserTokenInfo has store, drop, copy {
        user: address,
        token_id: address, // The token's type ID/address
        commission_bps: u64, // Fee in basis points (1/100 of a percent)
        creator_split_bps: u64, // Percentage of commission that goes to creator (in basis points)
        platform_split_bps: u64, // Percentage of commission that goes to platform (in basis points)
    }
    
    // Accessor functions for UserTokenInfo fields
    public fun user(info: &UserTokenInfo): address {
        info.user
    }
    
    public fun token_id(info: &UserTokenInfo): address {
        info.token_id
    }
    
    public fun commission_bps(info: &UserTokenInfo): u64 {
        info.commission_bps
    }
    
    public fun creator_split_bps(info: &UserTokenInfo): u64 {
        info.creator_split_bps
    }
    
    public fun platform_split_bps(info: &UserTokenInfo): u64 {
        info.platform_split_bps
    }
    
    /// A capability given to the user who owns a token
    /// Allows configuring token parameters but not minting/burning
    public struct UserTokenOwnership<phantom T> has key, store {
        id: UID,
        token_type: address, // The token's type ID
    }
    
    /// Fee collector for the user token
    /// This object collects the fees from trades and allows
    /// withdrawing by the authorized parties
    public struct FeeCollector<phantom T> has key, store {
        id: UID,
        creator_balance: Balance<T>,
        platform_balance: Balance<T>,
    }

    // === Events ===
    
    /// Event emitted when a new user token is created
    public struct TokenCreatedEvent has copy, drop {
        token_type: address,
        user: address,
        name: string::String,
        symbol: ascii::String,
        commission_bps: u64,
        creator_split_bps: u64,
        platform_split_bps: u64,
    }
    
    /// Event emitted when a token swap occurs
    public struct TokenSwapEvent has copy, drop {
        token_type: address,
        sender: address,
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        creator_fee: u64,
        platform_fee: u64,
    }
    
    /// Event emitted when token parameters are updated
    public struct TokenConfigUpdatedEvent has copy, drop {
        token_type: address,
        user: address,
        commission_bps: u64,
        creator_split_bps: u64,
        platform_split_bps: u64,
    }

    // === Initialization ===
    
    /// Initialize the user token system
    /// Creates the admin capability and token registry
    fun init(ctx: &mut TxContext) {
        // Create and transfer admin capability to the transaction sender
        transfer::public_transfer(
            AdminCap {
                id: object::new(ctx),
            },
            tx_context::sender(ctx)
        );
        
        // Create and share token registry
        transfer::share_object(
            TokenRegistry {
                id: object::new(ctx),
                tokens: vector::empty(),
            }
        );
    }
    
    // === Admin Functions ===
    
    /// Create a new user token. Only the admin can call this function.
    /// The treasury cap is kept by the module, and the user receives a
    /// UserTokenOwnership object that allows configuring token parameters.
    public entry fun create_user_token<T: drop>(
        admin_cap: &AdminCap,
        registry: &mut TokenRegistry,
        user: address,
        witness: T,
        decimals: u8,
        symbol: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        has_icon_url: bool,
        icon_url_bytes: vector<u8>,
        has_commission: bool,
        commission_bps: u64,
        has_creator_split: bool,
        creator_split_bps: u64,
        ctx: &mut TxContext
    ) {
        // Use coin::create_currency since user tokens don't need admin cap
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            decimals,
            symbol,
            name,
            description,
            if (has_icon_url) { 
                option::some(url::new_unsafe_from_bytes(icon_url_bytes)) 
            } else { 
                option::none() 
            },
            ctx,
        );
        
        // Use the object ID as the token type ID
        let token_type = object::id_address(&treasury_cap);
        
        // Check that user doesn't already have a token
        let mut i = 0;
        let len = vector::length(&registry.tokens);
        while (i < len) {
            let token_info = vector::borrow(&registry.tokens, i);
            assert!(token_info.user != user, ETokenAlreadyExists);
            i = i + 1;
        };
        
        // Get commission fee or use default
        let commission = if (has_commission) {
            assert!(commission_bps <= MAX_COMMISSION_BPS, EInvalidCommission);
            commission_bps
        } else {
            DEFAULT_COMMISSION_BPS
        };
        
        // Get creator split or use default
        let creator_split = if (has_creator_split) {
            assert!(creator_split_bps <= 10000, EInvalidFeeSplit);
            creator_split_bps
        } else {
            DEFAULT_CREATOR_SPLIT_BPS
        };
        
        // Calculate platform split
        let platform_split = 10000 - creator_split;
        assert!(platform_split <= MAX_PLATFORM_SPLIT_BPS, EInvalidFeeSplit);
        
        // Save token info to registry
        let token_info = UserTokenInfo {
            user,
            token_id: token_type,
            commission_bps: commission,
            creator_split_bps: creator_split,
            platform_split_bps: platform_split,
        };
        vector::push_back(&mut registry.tokens, token_info);
        
        // Create the fee collector
        let fee_collector = FeeCollector<T> {
            id: object::new(ctx),
            creator_balance: balance::zero(),
            platform_balance: balance::zero(),
        };
        
        // Give the user ownership capability
        let ownership = UserTokenOwnership<T> {
            id: object::new(ctx),
            token_type,
        };
        
        // Transfer ownership to the user
        transfer::public_transfer(ownership, user);
        
        // Share the fee collector
        transfer::public_share_object(fee_collector);
        
        // Keep treasury cap with admin
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        
        // Make a copy of metadata for the event before sharing
        let metadata_name = coin::get_name(&metadata);
        let metadata_symbol = coin::get_symbol(&metadata);
        
        // Share metadata
        transfer::public_share_object(metadata);
        
        // Emit event
        event::emit(TokenCreatedEvent {
            token_type,
            user,
            name: metadata_name,
            symbol: metadata_symbol,
            commission_bps: commission,
            creator_split_bps: creator_split,
            platform_split_bps: platform_split,
        });
    }
    
    /// Mint tokens for liquidity pool or distribution (admin only)
    public entry fun mint_tokens<T>(
        admin_cap: &AdminCap,
        treasury_cap: &mut TreasuryCap<T>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let minted_coin = coin::mint(treasury_cap, amount, ctx);
        transfer::public_transfer(minted_coin, recipient);
    }
    
    // === User Functions ===
    
    /// Update token commission settings
    public entry fun update_commission<T>(
        ownership: &UserTokenOwnership<T>,
        registry: &mut TokenRegistry,
        commission_bps: u64,
        creator_split_bps: u64,
        ctx: &mut TxContext
    ) {
        // Validate commission
        assert!(commission_bps <= MAX_COMMISSION_BPS, EInvalidCommission);
        
        // Validate creator split
        assert!(creator_split_bps <= 10000, EInvalidFeeSplit);
        
        // Calculate platform split
        let platform_split_bps = 10000 - creator_split_bps;
        assert!(platform_split_bps <= MAX_PLATFORM_SPLIT_BPS, EInvalidFeeSplit);
        
        // Get token type
        let token_type = ownership.token_type;
        
        // Find and update token info
        let user = tx_context::sender(ctx);
        let len = vector::length(&registry.tokens);
        let mut i = 0;
        let mut found = false;
        
        while (i < len) {
            let token_info = vector::borrow_mut(&mut registry.tokens, i);
            if (token_info.token_id == token_type && token_info.user == user) {
                token_info.commission_bps = commission_bps;
                token_info.creator_split_bps = creator_split_bps;
                token_info.platform_split_bps = platform_split_bps;
                found = true;
                break
            };
            i = i + 1;
        };
        
        assert!(found, ETokenNotRegistered);
        
        // Emit event
        event::emit(TokenConfigUpdatedEvent {
            token_type,
            user,
            commission_bps,
            creator_split_bps,
            platform_split_bps,
        });
    }
    
    /// Swap tokens - this is a simplified implementation
    /// In a real system, this would integrate with an orderbook or AMM
    public entry fun swap<T>(
        registry: &TokenRegistry,
        fee_collector: &mut FeeCollector<T>,
        coin_in: &mut Coin<T>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // In a real implementation, this would calculate the output amount
        // based on the token price from an orderbook or AMM pool
        
        // Get token info from the fee collector's object ID
        let token_type = object::id_address(fee_collector);
        let token_info = find_token_info(registry, token_type);
        
        // Calculate fees
        let fee_amount = (amount * token_info.commission_bps) / 10000;
        let creator_fee = (fee_amount * token_info.creator_split_bps) / 10000;
        let platform_fee = fee_amount - creator_fee;
        
        // Take fee from input coin
        if (fee_amount > 0) {
            let fee_coin = coin::split(coin_in, fee_amount, ctx);
            let mut fee_balance = coin::into_balance(fee_coin);
            
            // Split fee between creator and platform
            if (creator_fee > 0) {
                let creator_fee_balance = balance::split(&mut fee_balance, creator_fee);
                balance::join(&mut fee_collector.creator_balance, creator_fee_balance);
            };
            
            // Add remaining fee to platform
            balance::join(&mut fee_collector.platform_balance, fee_balance);
        };
        
        // Emit swap event
        let sender = tx_context::sender(ctx);
        event::emit(TokenSwapEvent {
            token_type,
            sender,
            amount_in: amount,
            amount_out: amount - fee_amount, // Simplified - just the net amount after fees
            fee_amount,
            creator_fee,
            platform_fee,
        });
    }
    
    /// Withdraw creator fees
    public entry fun withdraw_creator_fees<T>(
        ownership: &UserTokenOwnership<T>,
        fee_collector: &mut FeeCollector<T>,
        ctx: &mut TxContext
    ) {
        let creator = tx_context::sender(ctx);
        
        // Get token type
        let token_type = ownership.token_type;
        
        // Check that creator balance is not empty
        let creator_balance = balance::value(&fee_collector.creator_balance);
        assert!(creator_balance > 0, 0); // No fees to withdraw
        
        // Extract all creator fees
        let withdraw_balance = balance::split(&mut fee_collector.creator_balance, creator_balance);
        let withdraw_coin = coin::from_balance(withdraw_balance, ctx);
        
        // Transfer to creator
        transfer::public_transfer(withdraw_coin, creator);
    }
    
    /// Withdraw platform fees (admin only)
    public entry fun withdraw_platform_fees<T>(
        _admin_cap: &AdminCap,
        fee_collector: &mut FeeCollector<T>,
        ctx: &mut TxContext
    ) {
        let admin = tx_context::sender(ctx);
        
        // Check that platform balance is not empty
        let platform_balance = balance::value(&fee_collector.platform_balance);
        assert!(platform_balance > 0, 0); // No fees to withdraw
        
        // Extract all platform fees
        let withdraw_balance = balance::split(&mut fee_collector.platform_balance, platform_balance);
        let withdraw_coin = coin::from_balance(withdraw_balance, ctx);
        
        // Transfer to platform admin
        transfer::public_transfer(withdraw_coin, admin);
    }
    
    // === Utility Functions ===
    
    /// Find token info by token type address
    public fun find_token_info(registry: &TokenRegistry, token_type: address): UserTokenInfo {
        let len = vector::length(&registry.tokens);
        let mut i = 0;
        
        while (i < len) {
            let token_info = vector::borrow(&registry.tokens, i);
            if (token_info.token_id == token_type) {
                return *token_info
            };
            i = i + 1;
        };
        
        abort ETokenNotRegistered
    }
    
    /// Get user's token info
    public fun get_user_token_info(registry: &TokenRegistry, user: address): (bool, UserTokenInfo) {
        let len = vector::length(&registry.tokens);
        let mut i = 0;
        
        while (i < len) {
            let token_info = vector::borrow(&registry.tokens, i);
            if (token_info.user == user) {
                return (true, *token_info)
            };
            i = i + 1;
        };
        
        (false, UserTokenInfo {
            user,
            token_id: @0x0,
            commission_bps: 0,
            creator_split_bps: 0,
            platform_split_bps: 0,
        })
    }
    
    /// Check if user has a token
    public fun has_token(registry: &TokenRegistry, user: address): bool {
        let (has_token, _) = get_user_token_info(registry, user);
        has_token
    }
    
    /// Get token commission info
    public fun get_token_commission(registry: &TokenRegistry, token_type: address): (u64, u64, u64) {
        let token_info = find_token_info(registry, token_type);
        (token_info.commission_bps, token_info.creator_split_bps, token_info.platform_split_bps)
    }
    
    /// Get creator of a token
    public fun get_token_creator(registry: &TokenRegistry, token_type: address): address {
        let token_info = find_token_info(registry, token_type);
        token_info.user
    }
    
    /// Get available fees for a token creator
    public fun get_creator_available_fees<T>(fee_collector: &FeeCollector<T>): u64 {
        balance::value(&fee_collector.creator_balance)
    }
    
    /// Get available fees for the platform
    public fun get_platform_available_fees<T>(fee_collector: &FeeCollector<T>): u64 {
        balance::value(&fee_collector.platform_balance)
    }
    
    /// Get all registered token IDs
    public fun get_all_tokens(registry: &TokenRegistry): vector<address> {
        let mut result = vector::empty<address>();
        let len = vector::length(&registry.tokens);
        let mut i = 0;
        
        while (i < len) {
            let token_info = vector::borrow(&registry.tokens, i);
            vector::push_back(&mut result, token_info.token_id);
            i = i + 1;
        };
        
        result
    }
    
    // Removed duplicate function definition
    
    // Duplicate token swap event definition removed
}