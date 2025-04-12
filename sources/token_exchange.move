// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Token Exchange module for MySocial platform.
/// This module provides functionality for creation and trading of both profile tokens
/// and post tokens using an Automated Market Maker (AMM) with a quadratic pricing curve.
/// It includes fee distribution mechanisms for transactions, splitting between profile owner,
/// platform, and ecosystem treasury.
#[allow(unused_use, duplicate_alias, unused_const, unused_field, deprecated_usage)]
module social_contracts::token_exchange {
    use std::string::{Self, String};
    use std::ascii;
    use std::vector;
    use std::option::{Self, Option};
    
    use mys::object::{Self, UID, ID};
    use mys::tx_context::{Self, TxContext};
    use mys::transfer;
    use mys::event;
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::mys::MYS;
    use mys::balance::{Self, Balance};
    use mys::clock::{Self, Clock};
    use mys::math;
    
    use social_contracts::profile::{Self, Profile, UsernameRegistry};
    use social_contracts::post::{Self, Post};
    use social_contracts::block_list::{Self, BlockListRegistry};

    // === Error codes ===
    /// Operation can only be performed by the admin
    const ENotAuthorized: u64 = 0;
    /// Invalid fee percentages configuration
    const EInvalidFeeConfig: u64 = 1;
    /// The token already exists
    const ETokenAlreadyExists: u64 = 2;
    /// The token does not exist
    const ETokenNotFound: u64 = 3;
    /// Exceeded maximum token hold percentage
    const EExceededMaxHold: u64 = 4;
    /// Insufficient funds for operation
    const EInsufficientFunds: u64 = 5;
    /// Sender doesn't own any tokens
    const ENoTokensOwned: u64 = 6;
    /// Invalid post or profile ID
    const EInvalidID: u64 = 7;
    /// Insufficient token liquidity
    const EInsufficientLiquidity: u64 = 8;
    /// Self trading not allowed
    const ESelfTrading: u64 = 9;
    /// Token already initialized in pool
    const ETokenAlreadyInitialized: u64 = 10;
    /// Curve parameters must be positive
    const EInvalidCurveParams: u64 = 11;
    /// Invalid token type
    const EInvalidTokenType: u64 = 12;
    /// Viral threshold not met
    const EViralThresholdNotMet: u64 = 13;
    /// Auction already in progress
    const EAuctionInProgress: u64 = 14;
    /// Invalid auction duration
    const EInvalidAuctionDuration: u64 = 15;
    /// Auction not active
    const EAuctionNotActive: u64 = 16;
    /// Auction not ended
    const EAuctionNotEnded: u64 = 17;
    /// Auction already finalized
    const EAuctionAlreadyFinalized: u64 = 18;
    /// No contribution to auction
    const ENoContribution: u64 = 19;
    /// Cannot buy token from a blocked user
    const EBlockedUser: u64 = 20;

    // === Constants ===
    // Token types
    const TOKEN_TYPE_PROFILE: u8 = 1;
    const TOKEN_TYPE_POST: u8 = 2;

    // Default fee percentages (in basis points, 10000 = 100%)
    const DEFAULT_TOTAL_FEE_BPS: u64 = 150; // 1.5% total fee
    const DEFAULT_CREATOR_FEE_BPS: u64 = 100; // 1.0% to creator (profile/post owner)
    const DEFAULT_PLATFORM_FEE_BPS: u64 = 25; // 0.25% to platform
    const DEFAULT_TREASURY_FEE_BPS: u64 = 25; // 0.25% to ecosystem treasury

    // Maximum hold percentage per wallet (5% of supply)
    const MAX_HOLD_PERCENT_BPS: u64 = 500;

    // Default AMM curve parameters
    const DEFAULT_BASE_PRICE: u64 = 100_000_000; // 0.1 MYS in smallest units
    const DEFAULT_QUADRATIC_COEFFICIENT: u64 = 100_000; // Coefficient for quadratic curve

    // Viral threshold constants for posts
    const POST_LIKES_WEIGHT: u64 = 1;
    const POST_COMMENTS_WEIGHT: u64 = 3;
    const POST_TIPS_WEIGHT: u64 = 10;
    const POST_VIRAL_THRESHOLD: u64 = 100;

    // Viral threshold constants for profiles
    const PROFILE_FOLLOWS_WEIGHT: u64 = 1;
    const PROFILE_POSTS_WEIGHT: u64 = 1;
    const PROFILE_TIPS_WEIGHT: u64 = 5;
    const PROFILE_VIRAL_THRESHOLD: u64 = 100;

    // Auction duration limits (in seconds)
    const MIN_POST_AUCTION_DURATION: u64 = 1 * 60 * 60; // 1 hour
    const MAX_POST_AUCTION_DURATION: u64 = 3 * 60 * 60; // 3 hours
    const MIN_PROFILE_AUCTION_DURATION: u64 = 24 * 60 * 60; // 1 day
    const MAX_PROFILE_AUCTION_DURATION: u64 = 72 * 60 * 60; // 3 days

    // Auction status
    const AUCTION_STATUS_PENDING: u8 = 0;
    const AUCTION_STATUS_ACTIVE: u8 = 1;
    const AUCTION_STATUS_ENDED: u8 = 2;
    const AUCTION_STATUS_FINALIZED: u8 = 3;

    // === Structs ===

    /// Admin capability for the token exchange
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Global exchange configuration
    public struct ExchangeConfig has key {
        id: UID,
        /// Total fee percentage in basis points
        total_fee_bps: u64,
        /// Creator fee percentage in basis points
        creator_fee_bps: u64,
        /// Platform fee percentage in basis points
        platform_fee_bps: u64,
        /// Treasury fee percentage in basis points
        treasury_fee_bps: u64,
        /// Base price for new tokens
        base_price: u64,
        /// Quadratic coefficient for pricing curve
        quadratic_coefficient: u64,
        /// Platform treasury address
        platform_treasury: address,
        /// Ecosystem treasury address
        ecosystem_treasury: address,
        /// Maximum percentage a single wallet can hold of any token
        max_hold_percent_bps: u64,
    }

    /// Registry of all tokens in the exchange
    public struct TokenRegistry has key {
        id: UID,
        /// Table from token ID to token info
        tokens: Table<address, TokenInfo>,
        /// Table from profile/post ID to auction info
        auctions: Table<address, AuctionInfo>,
    }

    /// Information about a token
    public struct TokenInfo has store, copy, drop {
        /// The token ID (object ID of the pool)
        id: address,
        /// Type of token (1=profile, 2=post)
        token_type: u8,
        /// Owner/creator of the token
        owner: address,
        /// Associated profile or post ID
        associated_id: address,
        /// Token symbol
        symbol: String,
        /// Token name
        name: String,
        /// Current supply in circulation
        circulating_supply: u64,
        /// Base price for this token
        base_price: u64,
        /// Quadratic coefficient for this token's pricing curve
        quadratic_coefficient: u64,
        /// Creation timestamp
        created_at: u64,
    }

    /// Liquidity pool for a token
    public struct TokenPool has key {
        id: UID,
        /// The token's info
        info: TokenInfo,
        /// MYS balance in the pool
        mys_balance: Balance<MYS>,
        /// Mapping of holders' addresses to their token balances
        holders: Table<address, u64>,
    }

    /// Social token that represents a user's owned tokens
    public struct SocialToken has key, store {
        id: UID,
        /// Token pool ID
        pool_id: address,
        /// Token type (1=profile, 2=post)
        token_type: u8,
        /// Amount of tokens held
        amount: u64,
    }

    /// Information about an auction
    public struct AuctionInfo has store, copy, drop {
        /// Associated profile or post ID
        associated_id: address,
        /// Token type (1=profile, 2=post)
        token_type: u8,
        /// Owner of the profile/post
        owner: address,
        /// Status of the auction
        status: u8, // 0=pending, 1=active, 2=ended, 3=finalized
        /// Time when the auction was started
        start_time: u64,
        /// Duration of the auction in seconds
        duration: u64,
        /// Total MYS contributed to the auction
        total_contribution: u64,
        /// Total tokens to be distributed
        total_tokens: u64,
        /// List of contributors' addresses
        contributors: vector<address>,
    }

    /// Pre-launch auction pool
    public struct AuctionPool has key {
        id: UID,
        /// Auction info
        info: AuctionInfo,
        /// MYS balance contributed to the auction
        mys_balance: Balance<MYS>,
        /// Mapping of contributors' addresses to their MYS contributions
        contributions: Table<address, u64>,
    }

    // === Events ===

    /// Event emitted when a token pool is created
    public struct TokenPoolCreatedEvent has copy, drop {
        id: address,
        token_type: u8,
        owner: address,
        associated_id: address,
        symbol: String,
        name: String,
        base_price: u64,
        quadratic_coefficient: u64,
    }

    /// Event emitted when tokens are bought
    public struct TokenBoughtEvent has copy, drop {
        id: address,
        buyer: address,
        amount: u64,
        mys_amount: u64,
        fee_amount: u64,
        creator_fee: u64,
        platform_fee: u64,
        treasury_fee: u64,
        new_price: u64,
    }

    /// Event emitted when tokens are sold
    public struct TokenSoldEvent has copy, drop {
        id: address,
        seller: address,
        amount: u64,
        mys_amount: u64,
        fee_amount: u64,
        creator_fee: u64,
        platform_fee: u64,
        treasury_fee: u64,
        new_price: u64,
    }

    /// Event emitted when an auction is created
    public struct AuctionCreatedEvent has copy, drop {
        auction_id: address,
        associated_id: address,
        token_type: u8,
        owner: address,
        start_time: u64,
        duration: u64,
    }

    /// Event emitted when a user contributes to an auction
    public struct AuctionContributionEvent has copy, drop {
        auction_id: address,
        contributor: address,
        amount: u64,
        total_contribution: u64,
    }

    /// Event emitted when an auction is finalized
    public struct AuctionFinalizedEvent has copy, drop {
        auction_id: address,
        associated_id: address,
        total_contribution: u64,
        total_tokens: u64,
        token_price: u64,
        pool_id: address,
    }

    /// Event emitted when exchange config is updated
    public struct ConfigUpdatedEvent has copy, drop {
        total_fee_bps: u64,
        creator_fee_bps: u64,
        platform_fee_bps: u64,
        treasury_fee_bps: u64,
        base_price: u64,
        quadratic_coefficient: u64,
    }

    /// Event emitted when tokens are purchased by someone who already has a social token
    public struct TokensAddedEvent has copy, drop {
        owner: address, 
        pool_id: address,
        amount: u64,
    }

    // === Initialization ===
    
    /// Initialize the token exchange system
    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        
        // Create and transfer admin capability to the transaction sender
        transfer::public_transfer(
            AdminCap {
                id: object::new(ctx),
            },
            sender
        );
        
        // Create and share exchange config
        transfer::share_object(
            ExchangeConfig {
                id: object::new(ctx),
                total_fee_bps: DEFAULT_TOTAL_FEE_BPS,
                creator_fee_bps: DEFAULT_CREATOR_FEE_BPS,
                platform_fee_bps: DEFAULT_PLATFORM_FEE_BPS,
                treasury_fee_bps: DEFAULT_TREASURY_FEE_BPS,
                base_price: DEFAULT_BASE_PRICE,
                quadratic_coefficient: DEFAULT_QUADRATIC_COEFFICIENT,
                platform_treasury: sender, // Initially set to sender, should be updated
                ecosystem_treasury: sender, // Initially set to sender, should be updated
                max_hold_percent_bps: MAX_HOLD_PERCENT_BPS,
            }
        );
        
        // Create and share token registry
        transfer::share_object(
            TokenRegistry {
                id: object::new(ctx),
                tokens: table::new(ctx),
                auctions: table::new(ctx),
            }
        );
    }

    // === Admin Functions ===

    /// Update exchange configuration
    public entry fun update_config(
        _admin_cap: &AdminCap,
        config: &mut ExchangeConfig,
        total_fee_bps: u64, 
        creator_fee_bps: u64,
        platform_fee_bps: u64,
        treasury_fee_bps: u64,
        base_price: u64,
        quadratic_coefficient: u64,
        platform_treasury: address,
        ecosystem_treasury: address,
        max_hold_percent_bps: u64,
        _ctx: &mut TxContext
    ) {
        // Verify sum of fee percentages equals total
        assert!(creator_fee_bps + platform_fee_bps + treasury_fee_bps == total_fee_bps, EInvalidFeeConfig);
        
        // Verify curve parameters are valid
        assert!(base_price > 0 && quadratic_coefficient > 0, EInvalidCurveParams);
        
        // Update config
        config.total_fee_bps = total_fee_bps;
        config.creator_fee_bps = creator_fee_bps;
        config.platform_fee_bps = platform_fee_bps;
        config.treasury_fee_bps = treasury_fee_bps;
        config.base_price = base_price;
        config.quadratic_coefficient = quadratic_coefficient;
        config.platform_treasury = platform_treasury;
        config.ecosystem_treasury = ecosystem_treasury;
        config.max_hold_percent_bps = max_hold_percent_bps;
        
        // Emit config updated event
        event::emit(ConfigUpdatedEvent {
            total_fee_bps,
            creator_fee_bps,
            platform_fee_bps,
            treasury_fee_bps,
            base_price,
            quadratic_coefficient,
        });
    }

    // === Viral Threshold Checks ===

    /// Check if a post has reached the viral threshold
    public fun check_post_viral_threshold(
        post: &Post
    ): (bool, u64) {
        // Calculate viral score based on post metrics
        let likes = post::get_reaction_count(post) * POST_LIKES_WEIGHT;
        let comments = post::get_comment_count(post) * POST_COMMENTS_WEIGHT;
        let tips = post::get_tips_received(post) * POST_TIPS_WEIGHT;
        
        let viral_score = likes + comments + tips;
        
        // Check if the score exceeds the threshold
        (viral_score >= POST_VIRAL_THRESHOLD, viral_score)
    }
    
    /// Check if a profile has reached the viral threshold
    public fun check_profile_viral_threshold(
        profile: &Profile,
        _registry: &UsernameRegistry
    ): (bool, u64) {
        // Use accessor functions instead of direct field access
        let follows = profile::get_followers_count(profile) * PROFILE_FOLLOWS_WEIGHT;
        let posts = profile::get_post_count(profile) * PROFILE_POSTS_WEIGHT;
        let tips = profile::get_tips_received(profile) * PROFILE_TIPS_WEIGHT;
        
        let viral_score = follows + posts + tips;
        
        // Check if the score exceeds the threshold
        (viral_score >= PROFILE_VIRAL_THRESHOLD, viral_score)
    }
    
    // === Auction Functions ===
    
    /// Start a pre-launch auction for a post
    public entry fun start_post_auction(
        registry: &mut TokenRegistry,
        post: &Post,
        _symbol: vector<u8>,
        _name: vector<u8>,
        duration_hours: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let post_id = post::get_id_address(post);
        let owner = post::get_owner(post);
        
        // Verify caller is the post owner
        assert!(tx_context::sender(ctx) == owner, ENotAuthorized);
        
        // Check if an auction already exists for this post
        assert!(!table::contains(&registry.auctions, post_id), EAuctionInProgress);
        
        // Check if the post has reached the viral threshold
        let (is_viral, _viral_score) = check_post_viral_threshold(post);
        assert!(is_viral, EViralThresholdNotMet);
        
        // Validate auction duration
        let duration_seconds = duration_hours * 60 * 60;
        assert!(
            duration_seconds >= MIN_POST_AUCTION_DURATION && 
            duration_seconds <= MAX_POST_AUCTION_DURATION,
            EInvalidAuctionDuration
        );
        
        // Create auction info
        let start_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        let auction_info = AuctionInfo {
            associated_id: post_id,
            token_type: TOKEN_TYPE_POST,
            owner,
            status: AUCTION_STATUS_ACTIVE,
            start_time,
            duration: duration_seconds,
            total_contribution: 0,
            total_tokens: 0,
            contributors: vector::empty(),
        };
        
        // Create auction pool
        let auction_pool = AuctionPool {
            id: object::new(ctx),
            info: auction_info,
            mys_balance: balance::zero(),
            contributions: table::new(ctx),
        };
        
        // Add to registry
        table::add(&mut registry.auctions, post_id, auction_info);
        
        // Emit event
        event::emit(AuctionCreatedEvent {
            auction_id: object::uid_to_address(&auction_pool.id),
            associated_id: post_id,
            token_type: TOKEN_TYPE_POST,
            owner,
            start_time,
            duration: duration_seconds,
        });
        
        // Share the auction pool
        transfer::share_object(auction_pool);
    }
    
    /// Start a pre-launch auction for a profile
    public entry fun start_profile_auction(
        registry: &mut TokenRegistry,
        profile: &Profile,
        username_registry: &UsernameRegistry,
        _symbol: vector<u8>,
        _name: vector<u8>,
        duration_days: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let profile_id = profile::get_id_address(profile);
        let owner = profile::get_owner(profile);
        
        // Verify caller is the profile owner
        assert!(tx_context::sender(ctx) == owner, ENotAuthorized);
        
        // Check if an auction already exists for this profile
        assert!(!table::contains(&registry.auctions, profile_id), EAuctionInProgress);
        
        // Check if the profile has reached the viral threshold
        let (is_viral, _viral_score) = check_profile_viral_threshold(profile, username_registry);
        assert!(is_viral, EViralThresholdNotMet);
        
        // Validate auction duration
        let duration_seconds = duration_days * 24 * 60 * 60;
        assert!(
            duration_seconds >= MIN_PROFILE_AUCTION_DURATION && 
            duration_seconds <= MAX_PROFILE_AUCTION_DURATION,
            EInvalidAuctionDuration
        );
        
        // Create auction info
        let start_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        let auction_info = AuctionInfo {
            associated_id: profile_id,
            token_type: TOKEN_TYPE_PROFILE,
            owner,
            status: AUCTION_STATUS_ACTIVE,
            start_time,
            duration: duration_seconds,
            total_contribution: 0,
            total_tokens: 0,
            contributors: vector::empty(),
        };
        
        // Create auction pool
        let auction_pool = AuctionPool {
            id: object::new(ctx),
            info: auction_info,
            mys_balance: balance::zero(),
            contributions: table::new(ctx),
        };
        
        // Add to registry
        table::add(&mut registry.auctions, profile_id, auction_info);
        
        // Emit event
        event::emit(AuctionCreatedEvent {
            auction_id: object::uid_to_address(&auction_pool.id),
            associated_id: profile_id,
            token_type: TOKEN_TYPE_PROFILE,
            owner,
            start_time,
            duration: duration_seconds,
        });
        
        // Share the auction pool
        transfer::share_object(auction_pool);
    }
    
    /// Contribute MYS to an auction
    public entry fun contribute_to_auction(
        registry: &mut TokenRegistry,
        auction_pool: &mut AuctionPool,
        mut payment: Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let contributor = tx_context::sender(ctx);
        
        // Verify auction is active
        assert!(auction_pool.info.status == AUCTION_STATUS_ACTIVE, EAuctionNotActive);
        
        // Verify auction info matches registry
        let stored_info = table::borrow(&registry.auctions, auction_pool.info.associated_id);
        assert!(
            stored_info.owner == auction_pool.info.owner && 
            stored_info.start_time == auction_pool.info.start_time,
            EInvalidID
        );
        
        // Ensure contributor has enough funds
        assert!(coin::value(&payment) >= amount, EInsufficientFunds);
        
        // Extract payment
        let contribution = coin::split(&mut payment, amount, ctx);
        
        // Update contribution record
        if (table::contains(&auction_pool.contributions, contributor)) {
            let current_contribution = table::borrow_mut(&mut auction_pool.contributions, contributor);
            *current_contribution = *current_contribution + amount;
        } else {
            table::add(&mut auction_pool.contributions, contributor, amount);
            // Add to contributors list for tracking
            vector::push_back(&mut auction_pool.info.contributors, contributor);
        };
        
        // Add to pool balance
        balance::join(&mut auction_pool.mys_balance, coin::into_balance(contribution));
        
        // Update total contribution
        auction_pool.info.total_contribution = auction_pool.info.total_contribution + amount;
        
        // Update registry
        let mut updated_info = *stored_info;
        updated_info.total_contribution = auction_pool.info.total_contribution;
        
        // If this is a new contributor, add them to the registry's contributor list too
        if (!table::contains(&auction_pool.contributions, contributor)) {
            vector::push_back(&mut updated_info.contributors, contributor);
        };
        
        *table::borrow_mut(&mut registry.auctions, auction_pool.info.associated_id) = updated_info;
        
        // Return any excess payment
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, contributor);
        } else {
            coin::destroy_zero(payment);
        };
        
        // Emit contribution event
        event::emit(AuctionContributionEvent {
            auction_id: object::uid_to_address(&auction_pool.id),
            contributor,
            amount,
            total_contribution: auction_pool.info.total_contribution,
        });
    }
    
    /// Check if an auction has ended
    public fun is_auction_ended(
        auction_info: &AuctionInfo, 
        clock: &Clock
    ): bool {
        let current_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        let end_time = auction_info.start_time + auction_info.duration;
        current_time >= end_time
    }
    
    /// Finalize an auction and create the token pool
    /// This function checks if the auction has ended and finalizes it by creating a token pool
    public entry fun finalize_auction(
        registry: &mut TokenRegistry,
        config: &ExchangeConfig,
        auction_pool: &mut AuctionPool,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if auction has ended but status not updated
        if (auction_pool.info.status == AUCTION_STATUS_ACTIVE && is_auction_ended(&auction_pool.info, clock)) {
            // Update status to ended
            auction_pool.info.status = AUCTION_STATUS_ENDED;
            
            // Update registry
            let mut updated_info = *table::borrow(&registry.auctions, auction_pool.info.associated_id);
            updated_info.status = AUCTION_STATUS_ENDED;
            *table::borrow_mut(&mut registry.auctions, auction_pool.info.associated_id) = updated_info;
        };
        
        // Verify auction has ended
        assert!(auction_pool.info.status == AUCTION_STATUS_ENDED, EAuctionNotEnded);
        assert!(is_auction_ended(&auction_pool.info, clock), EAuctionNotEnded);
        
        // Verify auction has not been finalized
        assert!(
            !table::contains(&registry.tokens, auction_pool.info.associated_id),
            EAuctionAlreadyFinalized
        );
        
        // Verify there are contributions
        assert!(auction_pool.info.total_contribution > 0, ENoContribution);
        
        // Calculate initial token supply with dynamic scaling based on contribution size
        // This creates a non-linear relationship where larger pools get proportionally 
        // more tokens, helping to prevent front-running and maintain AMM efficiency
        
        // Use square root scaling to balance between very large and small pools
        // We use total_contribution^0.75 as our scaling factor
        // (Using integer math for the calculation)
        let contribution = auction_pool.info.total_contribution;
        let sqrt_contribution = math::sqrt(contribution);
        let cbrt_contribution = math::sqrt(sqrt_contribution); // approximation of cube root
        let mut scale_factor = sqrt_contribution * cbrt_contribution; // contribution^0.75
        
        // Divide the scale factor to make each token worth more than 1 MYSO
        // This ensures tokens are premium assets compared to the base currency
        scale_factor = scale_factor / 1000;
        
        // Apply different base multipliers for profile vs post tokens
        // Profile tokens have lower supply (more valuable per token)
        // Post tokens have higher supply (more collectible, less valuable per token)
        let mut initial_token_supply = if (auction_pool.info.token_type == TOKEN_TYPE_PROFILE) {
            // Profile tokens - lower supply (1x base multiplier)
            // These represent long-term investment in a person/brand
            scale_factor
        } else {
            // Post tokens - higher supply (10x base multiplier)
            // These are more collectible with many tokens per viral post
            scale_factor * 10
        };
        
        // Ensure we have at least 1 token
        if (initial_token_supply == 0) {
            initial_token_supply = 1;
        };
        
        let token_price = auction_pool.info.total_contribution / initial_token_supply;
        
        // Create token info
        let token_info = TokenInfo {
            id: @0x0, // Temporary, will be updated
            token_type: auction_pool.info.token_type,
            owner: auction_pool.info.owner,
            associated_id: auction_pool.info.associated_id,
            symbol: if (auction_pool.info.token_type == TOKEN_TYPE_PROFILE) {
                string::utf8(b"PUSER")
            } else {
                string::utf8(b"PPOST")
            },
            name: if (auction_pool.info.token_type == TOKEN_TYPE_PROFILE) {
                string::utf8(b"Profile Token")
            } else {
                string::utf8(b"Post Token")
            },
            circulating_supply: initial_token_supply,
            base_price: config.base_price,
            quadratic_coefficient: config.quadratic_coefficient,
            created_at: tx_context::epoch(ctx),
        };
        
        // Create token pool
        let pool_id = object::new(ctx);
        let pool_address = object::uid_to_address(&pool_id);
        
        // Create pool with updated token info
        let mut updated_token_info = token_info;
        updated_token_info.id = pool_address;
        
        let mut token_pool = TokenPool {
            id: pool_id,
            info: updated_token_info,
            mys_balance: balance::zero(),
            holders: table::new(ctx),
        };
        
        // Distribute tokens to contributors
        // Production implementation that efficiently distributes tokens to all contributors
        let contributors = &auction_pool.info.contributors;
        let num_contributors = vector::length(contributors);
        
        // Iterate through all contributors who participated in the auction
        let mut i = 0;
        while (i < num_contributors) {
            let contributor = *vector::borrow(contributors, i);
            let contribution_amount = *table::borrow(&auction_pool.contributions, contributor);
            
            // Calculate token amount based on contributor's proportion of total contribution
            let token_amount = (contribution_amount * initial_token_supply) / auction_pool.info.total_contribution;
            
            // Only process non-zero token amounts
            if (token_amount > 0) {
                // Update holder's balance in the pool
                table::add(&mut token_pool.holders, contributor, token_amount);
                
                // Create social token
                let social_token = SocialToken {
                    id: object::new(ctx),
                    pool_id: pool_address,
                    token_type: auction_pool.info.token_type,
                    amount: token_amount,
                };
                
                // Transfer social token to contributor
                transfer::public_transfer(social_token, contributor);
            };
            
            i = i + 1;
        };
        
        // Add contribution to pool balance
        balance::join(&mut token_pool.mys_balance, balance::withdraw_all(&mut auction_pool.mys_balance));
        
        // Update the registry
        table::add(&mut registry.tokens, auction_pool.info.associated_id, updated_token_info);
        
        // Update auction status
        auction_pool.info.status = AUCTION_STATUS_FINALIZED;
        auction_pool.info.total_tokens = initial_token_supply;
        
        // Update registry auction info
        let mut updated_auction_info = *table::borrow(&registry.auctions, auction_pool.info.associated_id);
        updated_auction_info.status = AUCTION_STATUS_FINALIZED;
        updated_auction_info.total_tokens = initial_token_supply;
        *table::borrow_mut(&mut registry.auctions, auction_pool.info.associated_id) = updated_auction_info;
        
        // Emit finalized event
        event::emit(AuctionFinalizedEvent {
            auction_id: object::uid_to_address(&auction_pool.id),
            associated_id: auction_pool.info.associated_id,
            total_contribution: auction_pool.info.total_contribution,
            total_tokens: initial_token_supply,
            token_price,
            pool_id: pool_address,
        });
        
        // Emit token created event
        event::emit(TokenPoolCreatedEvent {
            id: pool_address,
            token_type: updated_token_info.token_type,
            owner: updated_token_info.owner,
            associated_id: updated_token_info.associated_id,
            symbol: updated_token_info.symbol,
            name: updated_token_info.name,
            base_price: updated_token_info.base_price,
            quadratic_coefficient: updated_token_info.quadratic_coefficient,
        });
        
        // Share the token pool
        transfer::share_object(token_pool);
    }

    // === Trading Functions ===

    /// Buy tokens from the pool - first purchase
    /// This function handles buying tokens for first-time buyers of a specific token
    public entry fun buy_tokens(
        _registry: &TokenRegistry,
        pool: &mut TokenPool,
        config: &ExchangeConfig,
        block_list_registry: &BlockListRegistry,
        mut payment: Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let buyer = tx_context::sender(ctx);
        
        // Prevent self-trading for token owners
        assert!(buyer != pool.info.owner, ESelfTrading);
        
        // Check if token owner is blocked by the buyer
        assert!(!social_contracts::block_list::is_blocked(block_list_registry, buyer, pool.info.owner), EBlockedUser);
        
        // Calculate the price for the tokens based on quadratic curve
        let (price, _) = calculate_buy_price(
            pool.info.base_price,
            pool.info.quadratic_coefficient,
            pool.info.circulating_supply,
            amount
        );
        
        // Ensure buyer has enough funds
        assert!(coin::value(&payment) >= price, EInsufficientFunds);
        
        // Calculate fees
        let fee_amount = (price * config.total_fee_bps) / 10000;
        let creator_fee = (fee_amount * config.creator_fee_bps) / config.total_fee_bps;
        let platform_fee = (fee_amount * config.platform_fee_bps) / config.total_fee_bps;
        let treasury_fee = fee_amount - creator_fee - platform_fee;
        
        // Calculate the net amount to the liquidity pool
        let net_amount = price - fee_amount;
        
        // Extract payment and distribute fees directly
        if (fee_amount > 0) {
            // Send creator fee
            if (creator_fee > 0) {
                let creator_fee_coin = coin::split(&mut payment, creator_fee, ctx);
                transfer::public_transfer(creator_fee_coin, pool.info.owner);
            };
            
            // Send platform fee
            if (platform_fee > 0) {
                let platform_fee_coin = coin::split(&mut payment, platform_fee, ctx);
                transfer::public_transfer(platform_fee_coin, config.platform_treasury);
            };
            
            // Send treasury fee
            if (treasury_fee > 0) {
                let treasury_fee_coin = coin::split(&mut payment, treasury_fee, ctx);
                transfer::public_transfer(treasury_fee_coin, config.ecosystem_treasury);
            };
        };
        
        // Add remaining payment to pool
        let pool_payment = coin::split(&mut payment, net_amount, ctx);
        balance::join(&mut pool.mys_balance, coin::into_balance(pool_payment));
        
        // Refund any excess payment
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, buyer);
        } else {
            coin::destroy_zero(payment);
        };
        
        // Update holder's balance
        let max_hold = (pool.info.circulating_supply + amount) * config.max_hold_percent_bps / 10000;
        let current_hold = if (table::contains(&pool.holders, buyer)) {
            *table::borrow(&pool.holders, buyer)
        } else {
            0
        };
        
        // Check max holding limit
        assert!(current_hold + amount <= max_hold, EExceededMaxHold);
        
        // Check that this is the first purchase
        assert!(current_hold == 0, ETokenAlreadyExists);
        
        // Update holder's balance
        table::add(&mut pool.holders, buyer, amount);
        
        // Update circulating supply
        pool.info.circulating_supply = pool.info.circulating_supply + amount;
        
        // Mint new social token for the user
        let social_token = SocialToken {
            id: object::new(ctx),
            pool_id: object::uid_to_address(&pool.id),
            token_type: pool.info.token_type,
            amount,
        };
        transfer::public_transfer(social_token, buyer);
        
        // Calculate the new price after purchase
        let new_price = calculate_token_price(
            pool.info.base_price,
            pool.info.quadratic_coefficient,
            pool.info.circulating_supply
        );
        
        // Emit buy event
        event::emit(TokenBoughtEvent {
            id: object::uid_to_address(&pool.id),
            buyer,
            amount,
            mys_amount: price,
            fee_amount,
            creator_fee,
            platform_fee,
            treasury_fee,
            new_price,
        });
    }

    /// Buy more tokens when you already have a social token
    /// This function allows users to add to their existing token holdings using MYS Coin
    public entry fun buy_more_tokens(
        _registry: &TokenRegistry,
        pool: &mut TokenPool,
        config: &ExchangeConfig,
        block_list_registry: &BlockListRegistry,
        mut payment: Coin<MYS>,
        amount: u64,
        social_token: &mut SocialToken,
        ctx: &mut TxContext
    ) {
        let buyer = tx_context::sender(ctx);
        
        // Prevent self-trading for token owners
        assert!(buyer != pool.info.owner, ESelfTrading);
        
        // Check if token owner is blocked by the buyer
        assert!(!social_contracts::block_list::is_blocked(block_list_registry, buyer, pool.info.owner), EBlockedUser);
        
        // Verify social token matches the pool
        assert!(social_token.pool_id == object::uid_to_address(&pool.id), EInvalidID);
        
        // Calculate the price for the tokens based on quadratic curve
        let (price, _) = calculate_buy_price(
            pool.info.base_price,
            pool.info.quadratic_coefficient,
            pool.info.circulating_supply,
            amount
        );
        
        // Ensure buyer has enough funds
        assert!(coin::value(&payment) >= price, EInsufficientFunds);
        
        // Calculate fees
        let fee_amount = (price * config.total_fee_bps) / 10000;
        let creator_fee = (fee_amount * config.creator_fee_bps) / config.total_fee_bps;
        let platform_fee = (fee_amount * config.platform_fee_bps) / config.total_fee_bps;
        let treasury_fee = fee_amount - creator_fee - platform_fee;
        
        // Calculate the net amount to the liquidity pool
        let net_amount = price - fee_amount;
        
        // Extract payment and distribute fees directly
        if (fee_amount > 0) {
            // Send creator fee
            if (creator_fee > 0) {
                let creator_fee_coin = coin::split(&mut payment, creator_fee, ctx);
                transfer::public_transfer(creator_fee_coin, pool.info.owner);
            };
            
            // Send platform fee
            if (platform_fee > 0) {
                let platform_fee_coin = coin::split(&mut payment, platform_fee, ctx);
                transfer::public_transfer(platform_fee_coin, config.platform_treasury);
            };
            
            // Send treasury fee
            if (treasury_fee > 0) {
                let treasury_fee_coin = coin::split(&mut payment, treasury_fee, ctx);
                transfer::public_transfer(treasury_fee_coin, config.ecosystem_treasury);
            };
        };
        
        // Add remaining payment to pool
        let pool_payment = coin::split(&mut payment, net_amount, ctx);
        balance::join(&mut pool.mys_balance, coin::into_balance(pool_payment));
        
        // Refund any excess payment
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, buyer);
        } else {
            coin::destroy_zero(payment);
        };
        
        // Update holder's balance
        let max_hold = (pool.info.circulating_supply + amount) * config.max_hold_percent_bps / 10000;
        let current_hold = if (table::contains(&pool.holders, buyer)) {
            *table::borrow(&pool.holders, buyer)
        } else {
            0
        };
        
        // Check max holding limit
        assert!(current_hold + amount <= max_hold, EExceededMaxHold);
        
        // Update holder's balance
        if (table::contains(&pool.holders, buyer)) {
            let holder_balance = table::borrow_mut(&mut pool.holders, buyer);
            *holder_balance = *holder_balance + amount;
        } else {
            table::add(&mut pool.holders, buyer, amount);
        };
        
        // Update circulating supply
        pool.info.circulating_supply = pool.info.circulating_supply + amount;
        
        // Update the user's social token
        social_token.amount = social_token.amount + amount;
        
        // Calculate the new price after purchase
        let new_price = calculate_token_price(
            pool.info.base_price,
            pool.info.quadratic_coefficient,
            pool.info.circulating_supply
        );
        
        // Emit buy event
        event::emit(TokenBoughtEvent {
            id: object::uid_to_address(&pool.id),
            buyer,
            amount,
            mys_amount: price,
            fee_amount,
            creator_fee,
            platform_fee,
            treasury_fee,
            new_price,
        });
    }

    /// Sell tokens back to the pool
    public entry fun sell_tokens(
        _registry: &TokenRegistry,
        pool: &mut TokenPool,
        config: &ExchangeConfig,
        social_token: &mut SocialToken,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let seller = tx_context::sender(ctx);
        let pool_id = object::uid_to_address(&pool.id);
        
        // Verify social token matches the pool
        assert!(social_token.pool_id == pool_id, EInvalidID);
        assert!(social_token.amount >= amount, EInsufficientLiquidity);
        
        // Calculate the sell price based on quadratic curve
        let (refund_amount, _) = calculate_sell_price(
            pool.info.base_price,
            pool.info.quadratic_coefficient,
            pool.info.circulating_supply,
            amount
        );
        
        // Calculate fees
        let fee_amount = (refund_amount * config.total_fee_bps) / 10000;
        let creator_fee = (fee_amount * config.creator_fee_bps) / config.total_fee_bps;
        let platform_fee = (fee_amount * config.platform_fee_bps) / config.total_fee_bps;
        let treasury_fee = fee_amount - creator_fee - platform_fee;
        
        // Calculate net refund
        let net_refund = refund_amount - fee_amount;
        
        // Ensure pool has enough liquidity
        assert!(balance::value(&pool.mys_balance) >= net_refund, EInsufficientLiquidity);
        
        // Update holder balance
        let holder_balance = table::borrow_mut(&mut pool.holders, seller);
        *holder_balance = *holder_balance - amount;
        
        // Update user's social token
        social_token.amount = social_token.amount - amount;
        
        // Update circulating supply
        pool.info.circulating_supply = pool.info.circulating_supply - amount;
        
        // Extract net refund from pool
        let refund_balance = balance::split(&mut pool.mys_balance, net_refund);
        
        // Process and distribute fees
        if (fee_amount > 0) {
            // Send fee to creator
            if (creator_fee > 0) {
                let creator_fee_coin = coin::from_balance(balance::split(&mut pool.mys_balance, creator_fee), ctx);
                transfer::public_transfer(creator_fee_coin, pool.info.owner);
            };
            
            // Send fee to platform
            if (platform_fee > 0) {
                let platform_fee_coin = coin::from_balance(balance::split(&mut pool.mys_balance, platform_fee), ctx);
                transfer::public_transfer(platform_fee_coin, config.platform_treasury);
            };
            
            // Send fee to treasury
            if (treasury_fee > 0) {
                let treasury_fee_coin = coin::from_balance(balance::split(&mut pool.mys_balance, treasury_fee), ctx);
                transfer::public_transfer(treasury_fee_coin, config.ecosystem_treasury);
            };
        };
        
        // Transfer refund to seller
        let refund_coin = coin::from_balance(refund_balance, ctx);
        transfer::public_transfer(refund_coin, seller);
        
        // Calculate the new price after sale
        let new_price = calculate_token_price(
            pool.info.base_price,
            pool.info.quadratic_coefficient,
            pool.info.circulating_supply
        );
        
        // Emit sell event
        event::emit(TokenSoldEvent {
            id: pool_id,
            seller,
            amount,
            mys_amount: refund_amount,
            fee_amount,
            creator_fee,
            platform_fee,
            treasury_fee,
            new_price,
        });
    }

    // === Utility Functions ===

    /// Calculate token price at current supply based on quadratic curve
    /// Price = base_price + (quadratic_coefficient * supply^2)
    public fun calculate_token_price(
        base_price: u64,
        quadratic_coefficient: u64,
        supply: u64
    ): u64 {
        let squared_supply = supply * supply;
        base_price + (quadratic_coefficient * squared_supply / 10000)
    }

    /// Calculate price to buy a specific amount of tokens
    /// Returns (total price, average price per token)
    public fun calculate_buy_price(
        base_price: u64,
        quadratic_coefficient: u64,
        current_supply: u64,
        amount: u64
    ): (u64, u64) {
        let mut total_price = 0;
        let mut current = current_supply;
        let mut i = 0;
        
        // Integrate the price curve over the purchase amount
        while (i < amount) {
            let token_price = calculate_token_price(base_price, quadratic_coefficient, current);
            total_price = total_price + token_price;
            current = current + 1;
            i = i + 1;
        };
        
        let avg_price = if (amount > 0) {
            total_price / amount
        } else {
            0
        };
        
        (total_price, avg_price)
    }

    /// Calculate refund amount when selling tokens
    /// Returns (total refund, average price per token)
    public fun calculate_sell_price(
        base_price: u64,
        quadratic_coefficient: u64,
        current_supply: u64,
        amount: u64
    ): (u64, u64) {
        let mut total_refund = 0;
        let mut current = current_supply;
        let mut i = 0;
        
        // Integrate the price curve over the sell amount
        while (i < amount) {
            current = current - 1;
            let token_price = calculate_token_price(base_price, quadratic_coefficient, current);
            total_refund = total_refund + token_price;
            i = i + 1;
        };
        
        let avg_price = if (amount > 0) {
            total_refund / amount
        } else {
            0
        };
        
        (total_refund, avg_price)
    }

    /// Get token info from registry
    public fun get_token_info(registry: &TokenRegistry, id: address): TokenInfo {
        assert!(table::contains(&registry.tokens, id), ETokenNotFound);
        *table::borrow(&registry.tokens, id)
    }

    /// Get token owner's address
    public fun get_token_owner(registry: &TokenRegistry, id: address): address {
        let info = get_token_info(registry, id);
        info.owner
    }

    /// Get current token price for a specific pool
    public fun get_pool_price(pool: &TokenPool): u64 {
        calculate_token_price(
            pool.info.base_price, 
            pool.info.quadratic_coefficient,
            pool.info.circulating_supply
        )
    }

    /// Get user's token balance
    public fun get_user_balance(pool: &TokenPool, user: address): u64 {
        if (table::contains(&pool.holders, user)) {
            *table::borrow(&pool.holders, user)
        } else {
            0
        }
    }

    // Test-only functions
    #[test_only]
    /// Initialize the token exchange for testing
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
} 