// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Universal transaction sponsorship module for MySocial network
/// Allows any authorized sponsor to pay gas fees for user transactions
/// and optionally distribute initial tokens to new users
module social_contracts::sponsor {
    use std::string::String;
    use std::ascii::String as AsciiString;
    use std::vector;
    
    use mys::object::{Self, UID};
    use mys::tx_context::{Self, TxContext};
    use mys::transfer;
    use mys::event;
    use mys::coin::{Self, Coin};
    use mys::package::{Publisher};
    use mys::clock::{Self, Clock};
    
    use social_contracts::profile::{Self, Profile};
    use social_contracts::user_token::{Self, AdminCap, TokenRegistry};

    /// Error codes
    const ENotAuthorized: u64 = 0;
    const EProfileAlreadyExists: u64 = 1;
    const EInvalidAmount: u64 = 2;
    const EInvalidDuration: u64 = 3;
    const EUserNotEligible: u64 = 4;
    const ESponsorNotRegistered: u64 = 5;
    const EQuotaExceeded: u64 = 6;
    const EInvalidLimit: u64 = 7;
    const EInvalidRate: u64 = 8;
    const ESponsorAlreadyRegistered: u64 = 9;
    const ERateLimitExceeded: u64 = 10;
    const EClockRequired: u64 = 11;

    // ==================== Capabilities and permissions ====================

    /// Admin capability for managing the sponsorship system
    public struct SponsorshipAdmin has key, store {
        id: UID,
        /// The address of the admin
        sponsor: address,
        /// Default amount of tokens to distribute to new users (if enabled)
        default_token_amount: u64,
        /// Flag to control token distribution
        enable_token_distribution: bool,
        /// Email verification requirement
        require_email_verification: bool,
        /// Default daily quota for sponsored transactions per user
        default_daily_tx_quota: u64,
        /// Maximum number of transactions any user can sponsor
        max_daily_tx_quota: u64,
    }

    /// Capability to act as a sponsor
    /// Can be used by:
    /// 1. MySocial admins for universal sponsorship
    /// 2. Apps/dApps for sponsoring their users
    /// 3. Individual users willing to sponsor others
    public struct SponsorCapability has key, store {
        id: UID,
        /// The address of the sponsor (who pays for gas)
        sponsor: address,
        /// Optional sponsor name
        name: AsciiString, 
        /// Daily quota for transactions
        daily_tx_quota: u64,
        /// Whether the sponsor is enabled (can be disabled by admin)
        enabled: bool,
        /// Number of transactions sponsored today
        today_sponsored_count: u64,
        /// Last reset timestamp
        last_reset_day: u64,
        /// Tag for categorizing sponsors
        sponsor_type: u8,
    }

    // ==================== User state tracking ====================

    /// Tracks a user's sponsorship status
    public struct UserSponsorshipInfo has key, store {
        id: UID,
        /// User address
        user: address,
        /// Map of sponsors used today and count from each
        /// We use a vector representation here
        sponsored_today: vector<SponsoredBy>,
        /// Total count of sponsored transactions today
        today_count: u64,
        /// Last day when counts were reset
        last_reset_day: u64,
        /// Whether user has received initial tokens
        received_initial_tokens: bool,
        /// Whether user has a verified email
        email_verified: bool,
    }

    /// Represents a sponsor used by a user today
    public struct SponsoredBy has store, copy, drop {
        sponsor: address,
        count: u64,
    }

    // ==================== Events ====================

    /// Event emitted when a transaction is sponsored
    public struct TransactionSponsoredEvent has copy, drop {
        sponsor: address,
        user: address,
        sponsored_at: u64,
        sponsor_daily_count: u64,
        user_daily_count: u64,
        sponsor_type: u8,
    }

    /// Event emitted when tokens are distributed
    public struct TokensDistributedEvent has copy, drop {
        sponsor: address,
        user: address,
        amount: u64,
        distributed_at: u64,
    }
    
    /// Event emitted when a specific action is sponsored
    public struct SponsoredActionEvent has copy, drop {
        sponsor: address,
        user: address,
        action_type: AsciiString,
        sponsored_at: u64,
        sponsor_daily_count: u64,
        sponsor_type: u8,
    }

    /// Event emitted when a sponsor is registered
    public struct SponsorRegisteredEvent has copy, drop {
        sponsor: address,
        name: AsciiString,
        daily_quota: u64,
        sponsor_type: u8,
        registered_at: u64,
    }

    /// Event emitted when sponsorship settings are updated
    public struct SponsorshipConfigUpdatedEvent has copy, drop {
        default_token_amount: u64,
        enable_token_distribution: bool,
        require_email_verification: bool,
        default_daily_tx_quota: u64,
        max_daily_tx_quota: u64,
        updated_at: u64,
    }

    // ==================== Constants ====================

    // Sponsor types
    const SPONSOR_TYPE_ADMIN: u8 = 0;
    const SPONSOR_TYPE_APP: u8 = 1;
    const SPONSOR_TYPE_INDIVIDUAL: u8 = 2;

    // Milliseconds in a day
    const MS_PER_DAY: u64 = 86400000; // 24 * 60 * 60 * 1000;

    // ==================== Initialization and setup ====================

    /// Initialize with default settings
    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        
        let admin = SponsorshipAdmin {
            id: object::new(ctx),
            sponsor: sender,
            default_token_amount: 1000000000, // 10 tokens with 8 decimals
            enable_token_distribution: true,
            require_email_verification: false,
            default_daily_tx_quota: 20, // 20 transactions per day
            max_daily_tx_quota: 1000, // 1000 transactions per day maximum
        };

        // Transfer to deployer
        transfer::transfer(admin, sender);
    }

    /// Register a new sponsor (admin only)
    public entry fun register_sponsor(
        admin: &SponsorshipAdmin,
        name: vector<u8>,
        sponsor: address,
        daily_quota: u64,
        sponsor_type: u8,
        ctx: &mut TxContext
    ) {
        // Check if called by admin
        assert!(tx_context::sender(ctx) == admin.sponsor, ENotAuthorized);
        
        // Validate quota
        assert!(daily_quota > 0 && daily_quota <= admin.max_daily_tx_quota, EInvalidLimit);
        
        // Create sponsor capability
        let sponsor_cap = SponsorCapability {
            id: object::new(ctx),
            sponsor,
            name: std::ascii::string(name),
            daily_tx_quota: daily_quota,
            enabled: true,
            today_sponsored_count: 0,
            last_reset_day: get_day_from_tx(ctx),
            sponsor_type,
        };
        
        // Emit registration event
        event::emit(SponsorRegisteredEvent {
            sponsor,
            name: sponsor_cap.name,
            daily_quota,
            sponsor_type,
            registered_at: tx_context::epoch_timestamp_ms(ctx),
        });
        
        // Transfer to the sponsor
        transfer::transfer(sponsor_cap, sponsor);
    }

    // ==================== Sponsorship logic ====================

    /// Record a sponsored transaction
    /// This should be called when the sponsor/gas station signs a transaction
    /// Called by an off-chain service after sponsoring a transaction
    public entry fun record_sponsored_transaction(
        sponsor_cap: &mut SponsorCapability,
        user: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if called by sponsor
        assert!(tx_context::sender(ctx) == sponsor_cap.sponsor, ENotAuthorized);
        
        // Check if sponsor is enabled
        assert!(sponsor_cap.enabled, ENotAuthorized);
        
        // Update day and potentially reset counts
        let current_day = clock::timestamp_ms(clock) / MS_PER_DAY;
        if (current_day > sponsor_cap.last_reset_day) {
            sponsor_cap.today_sponsored_count = 0;
            sponsor_cap.last_reset_day = current_day;
        };
        
        // Check quota
        assert!(sponsor_cap.today_sponsored_count < sponsor_cap.daily_tx_quota, EQuotaExceeded);
        
        // Update sponsor stats
        sponsor_cap.today_sponsored_count = sponsor_cap.today_sponsored_count + 1;
        
        // Get or create user info
        let user_info_opt = get_or_create_user_info(user, current_day, ctx);
        
        // Update user stats
        // We'll handle this in the off-chain service for simplicity
        // since UserSponsorshipInfo should be owned by the user
        
        // Emit event
        event::emit(TransactionSponsoredEvent {
            sponsor: sponsor_cap.sponsor,
            user,
            sponsored_at: clock::timestamp_ms(clock),
            sponsor_daily_count: sponsor_cap.today_sponsored_count,
            user_daily_count: 1, // Placeholder since we don't have the actual count
            sponsor_type: sponsor_cap.sponsor_type,
        });
        
        // Transfer user info to user
        transfer::transfer(user_info_opt, user);
    }

    /// Helper to create user info if it doesn't exist
    fun get_or_create_user_info(
        user: address,
        current_day: u64,
        ctx: &mut TxContext
    ): UserSponsorshipInfo {
        // In a real implementation, this would first check if user info exists
        // For simplicity, we create a new one here
        UserSponsorshipInfo {
            id: object::new(ctx),
            user,
            sponsored_today: vector::empty<SponsoredBy>(),
            today_count: 0,
            last_reset_day: current_day,
            received_initial_tokens: false,
            email_verified: false,
        }
    }

    /// Distribute initial tokens to a user (admin or authorized sponsors only)
    public entry fun distribute_initial_tokens<T>(
        admin: &SponsorshipAdmin,
        treasury_cap: &mut coin::TreasuryCap<T>,
        admin_cap: &AdminCap,
        user: address,
        custom_amount: u64,
        ctx: &mut TxContext
    ) {
        // Check if called by admin
        assert!(tx_context::sender(ctx) == admin.sponsor, ENotAuthorized);
        
        // Get or create user info
        let mut user_info = get_or_create_user_info(user, get_day_from_tx(ctx), ctx);
        
        // Check if user already received tokens
        if (!user_info.received_initial_tokens) {
            // Determine amount to distribute
            let amount = if (custom_amount > 0) { 
                custom_amount 
            } else { 
                admin.default_token_amount 
            };
            
            // Mint and distribute tokens to the user
            user_token::mint_tokens(
                admin_cap,
                treasury_cap,
                amount,
                user,
                ctx
            );
            
            // Mark as received
            user_info.received_initial_tokens = true;
            
            // Emit token distribution event
            event::emit(TokensDistributedEvent {
                sponsor: tx_context::sender(ctx),
                user,
                amount,
                distributed_at: tx_context::epoch_timestamp_ms(ctx),
            });
        };
        
        // Transfer user info to user
        transfer::transfer(user_info, user);
    }

    /// Mark user email as verified (admin only)
    public entry fun mark_email_verified(
        admin: &SponsorshipAdmin,
        user_info: &mut UserSponsorshipInfo,
        ctx: &mut TxContext
    ) {
        // Check if called by admin
        assert!(tx_context::sender(ctx) == admin.sponsor, ENotAuthorized);
        
        user_info.email_verified = true;
    }

    // ==================== Admin and configuration functions ====================

    /// Update sponsorship configuration (admin only)
    public entry fun update_sponsorship_config(
        admin: &mut SponsorshipAdmin,
        default_token_amount: u64,
        enable_token_distribution: bool,
        require_email_verification: bool,
        default_daily_tx_quota: u64,
        max_daily_tx_quota: u64,
        ctx: &mut TxContext
    ) {
        // Check if called by admin
        assert!(tx_context::sender(ctx) == admin.sponsor, ENotAuthorized);
        
        // Validate quotas
        assert!(default_daily_tx_quota > 0, EInvalidLimit);
        assert!(max_daily_tx_quota >= default_daily_tx_quota, EInvalidLimit);
        
        // Update config
        admin.default_token_amount = default_token_amount;
        admin.enable_token_distribution = enable_token_distribution;
        admin.require_email_verification = require_email_verification;
        admin.default_daily_tx_quota = default_daily_tx_quota;
        admin.max_daily_tx_quota = max_daily_tx_quota;
        
        // Emit event
        event::emit(SponsorshipConfigUpdatedEvent {
            default_token_amount,
            enable_token_distribution,
            require_email_verification,
            default_daily_tx_quota,
            max_daily_tx_quota,
            updated_at: tx_context::epoch_timestamp_ms(ctx),
        });
    }

    /// Update a sponsor's quota and status (admin only)
    public entry fun update_sponsor(
        admin: &SponsorshipAdmin,
        sponsor_cap: &mut SponsorCapability,
        daily_quota: u64,
        enabled: bool,
        ctx: &mut TxContext
    ) {
        // Check if called by admin
        assert!(tx_context::sender(ctx) == admin.sponsor, ENotAuthorized);
        
        // Validate quota
        assert!(daily_quota <= admin.max_daily_tx_quota, EInvalidLimit);
        
        // Update sponsor
        if (daily_quota > 0) {
            sponsor_cap.daily_tx_quota = daily_quota;
        };
        sponsor_cap.enabled = enabled;
    }

    // ==================== App/dApp and individual sponsorship functions ====================

    /// Register your app as a sponsor (requires app publisher)
    public entry fun register_app_as_sponsor(
        admin: &SponsorshipAdmin,
        publisher: &Publisher,
        app_name: vector<u8>,
        daily_quota: u64,
        ctx: &mut TxContext
    ) {
        // Get publisher address from sender
        let publisher_address = tx_context::sender(ctx);
        
        // Validate quota
        assert!(daily_quota > 0 && daily_quota <= admin.max_daily_tx_quota, EInvalidLimit);
        
        // Create sponsor capability
        let sponsor_cap = SponsorCapability {
            id: object::new(ctx),
            sponsor: publisher_address,
            name: std::ascii::string(app_name),
            daily_tx_quota: daily_quota,
            enabled: true,
            today_sponsored_count: 0,
            last_reset_day: get_day_from_tx(ctx),
            sponsor_type: SPONSOR_TYPE_APP,
        };
        
        // Emit registration event
        event::emit(SponsorRegisteredEvent {
            sponsor: publisher_address,
            name: sponsor_cap.name,
            daily_quota,
            sponsor_type: SPONSOR_TYPE_APP,
            registered_at: tx_context::epoch_timestamp_ms(ctx),
        });
        
        // Transfer to the app
        transfer::transfer(sponsor_cap, publisher_address);
    }
    
    /// Register yourself as an individual sponsor
    /// This allows individuals to sponsor transactions for friends, family, etc.
    public entry fun register_individual_sponsor(
        admin: &SponsorshipAdmin,
        name: vector<u8>,
        daily_quota: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Validate quota - individual sponsors have lower limits
        let max_individual_quota = if (admin.max_daily_tx_quota > 50) { 50 } else { admin.max_daily_tx_quota };
        assert!(daily_quota > 0 && daily_quota <= max_individual_quota, EInvalidLimit);
        
        // Create sponsor capability
        let sponsor_cap = SponsorCapability {
            id: object::new(ctx),
            sponsor: sender,
            name: std::ascii::string(name),
            daily_tx_quota: daily_quota,
            enabled: true,
            today_sponsored_count: 0,
            last_reset_day: get_day_from_tx(ctx),
            sponsor_type: SPONSOR_TYPE_INDIVIDUAL,
        };
        
        // Emit registration event
        event::emit(SponsorRegisteredEvent {
            sponsor: sender,
            name: sponsor_cap.name,
            daily_quota,
            sponsor_type: SPONSOR_TYPE_INDIVIDUAL,
            registered_at: tx_context::epoch_timestamp_ms(ctx),
        });
        
        // Transfer to the individual
        transfer::transfer(sponsor_cap, sender);
    }

    // ==================== Helper functions ====================

    /// Convert TxContext to current day number for rate limiting
    fun get_day_from_tx(ctx: &TxContext): u64 {
        tx_context::epoch_timestamp_ms(ctx) / MS_PER_DAY
    }
    
    /// Fund a user account with tokens
    /// This universal function can be used to fund any user account regardless of purpose
    public entry fun fund_user_account<T>(
        sponsor_cap: &mut SponsorCapability,
        admin: &SponsorshipAdmin,
        treasury_cap: &mut coin::TreasuryCap<T>,
        admin_cap: &AdminCap,
        user: address,
        custom_amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if called by sponsor
        assert!(tx_context::sender(ctx) == sponsor_cap.sponsor, ENotAuthorized);
        
        // Check if sponsor is enabled
        assert!(sponsor_cap.enabled, ENotAuthorized);
        
        // Update day and potentially reset counts
        let current_day = clock::timestamp_ms(clock) / MS_PER_DAY;
        if (current_day > sponsor_cap.last_reset_day) {
            sponsor_cap.today_sponsored_count = 0;
            sponsor_cap.last_reset_day = current_day;
        };
        
        // Check quota
        assert!(sponsor_cap.today_sponsored_count < sponsor_cap.daily_tx_quota, EQuotaExceeded);
        
        // Update sponsor stats
        sponsor_cap.today_sponsored_count = sponsor_cap.today_sponsored_count + 1;
        
        // Get or create user info
        let mut user_info = get_or_create_user_info(user, current_day, ctx);
        
        // If token distribution is enabled and user hasn't received tokens yet
        if (admin.enable_token_distribution && !user_info.received_initial_tokens) {
            // Check if email verification is required
            if (!admin.require_email_verification || user_info.email_verified) {
                // Determine amount to distribute
                let amount = if (custom_amount > 0) { 
                    custom_amount 
                } else { 
                    admin.default_token_amount 
                };
                
                // Mint and distribute tokens to the user
                user_token::mint_tokens(
                    admin_cap,
                    treasury_cap,
                    amount,
                    user,
                    ctx
                );
                
                // Mark as received
                user_info.received_initial_tokens = true;
                
                // Emit token distribution event
                event::emit(TokensDistributedEvent {
                    sponsor: sponsor_cap.sponsor,
                    user,
                    amount,
                    distributed_at: clock::timestamp_ms(clock),
                });
            };
        };
        
        // Emit sponsored transaction event
        event::emit(TransactionSponsoredEvent {
            sponsor: sponsor_cap.sponsor,
            user,
            sponsored_at: clock::timestamp_ms(clock),
            sponsor_daily_count: sponsor_cap.today_sponsored_count,
            user_daily_count: 1, // Placeholder for user count
            sponsor_type: sponsor_cap.sponsor_type,
        });
        
        // Transfer user info to user
        transfer::transfer(user_info, user);
    }
    
    /// Record a sponsored action for a user
    /// This universal function can be used to record any sponsored action
    /// without coupling to specific transaction types
    public entry fun record_sponsored_action(
        sponsor_cap: &mut SponsorCapability,
        user: address,
        action_type: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if called by sponsor
        assert!(tx_context::sender(ctx) == sponsor_cap.sponsor, ENotAuthorized);
        
        // Check if sponsor is enabled
        assert!(sponsor_cap.enabled, ENotAuthorized);
        
        // Update day and potentially reset counts
        let current_day = clock::timestamp_ms(clock) / MS_PER_DAY;
        if (current_day > sponsor_cap.last_reset_day) {
            sponsor_cap.today_sponsored_count = 0;
            sponsor_cap.last_reset_day = current_day;
        };
        
        // Check quota
        assert!(sponsor_cap.today_sponsored_count < sponsor_cap.daily_tx_quota, EQuotaExceeded);
        
        // Update sponsor stats
        sponsor_cap.today_sponsored_count = sponsor_cap.today_sponsored_count + 1;
        
        // Get or create user info
        let user_info = get_or_create_user_info(user, current_day, ctx);
        
        // Emit sponsored action event with action type
        event::emit(SponsoredActionEvent {
            sponsor: sponsor_cap.sponsor,
            user,
            action_type: std::ascii::string(action_type),
            sponsored_at: clock::timestamp_ms(clock),
            sponsor_daily_count: sponsor_cap.today_sponsored_count,
            sponsor_type: sponsor_cap.sponsor_type,
        });
        
        // Transfer user info to user
        transfer::transfer(user_info, user);
    }

    // ==================== Accessors and getters ====================
    
    /// Get sponsor info
    public fun get_sponsor_info(cap: &SponsorCapability): (address, AsciiString, u64, bool, u64, u8) {
        (
            cap.sponsor,
            cap.name,
            cap.daily_tx_quota,
            cap.enabled,
            cap.today_sponsored_count,
            cap.sponsor_type
        )
    }
    
    /// Get user sponsorship info
    public fun get_user_info(info: &UserSponsorshipInfo): (address, u64, u64, bool, bool) {
        (
            info.user,
            info.today_count,
            info.last_reset_day,
            info.received_initial_tokens,
            info.email_verified
        )
    }
    
    /// Get sponsorship config
    public fun get_sponsorship_config(admin: &SponsorshipAdmin): (u64, bool, bool, u64, u64) {
        (
            admin.default_token_amount,
            admin.enable_token_distribution,
            admin.require_email_verification,
            admin.default_daily_tx_quota,
            admin.max_daily_tx_quota
        )
    }
}