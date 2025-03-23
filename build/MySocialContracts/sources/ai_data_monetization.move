// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// AI Data Monetization module for MySocial network.
/// This module enables users to opt-in to monetize their data through AI agents,
/// with revenue sharing between users, platforms, and MySocial.
module social_contracts::ai_data_monetization {
    use std::vector;
    use std::string::{Self, String};
    use mys::object::{Self, UID, ID};
    use mys::transfer;
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::balance::{Self, Balance};
    use mys::mys::MYS;
    
    use social_contracts::ai_agent_mpc::{Self, AgentCap};
    use social_contracts::ai_agent_integration::{Self};
    use social_contracts::platform::{Self, Platform};
    use social_contracts::profile::{Self, Profile};
    use social_contracts::fee_distribution::{Self, FeeRegistry};
    
    // === Errors ===
    /// Unauthorized operation
    const EUnauthorized: u64 = 0;
    /// Agent not registered
    const EAgentNotRegistered: u64 = 1;
    /// User not opted in for monetization
    const EUserNotOptedIn: u64 = 2;
    /// Invalid fee configuration
    const EInvalidFeeConfig: u64 = 3;
    /// Insufficient balance
    const EInsufficientBalance: u64 = 4;
    /// Invalid payment amount
    const EInvalidPayment: u64 = 5;
    /// Withdrawal exceeds available balance
    const EWithdrawalExceedsBalance: u64 = 6;
    
    // === Data Usage Types ===
    /// Analytics usage
    const USAGE_ANALYTICS: u8 = 0;
    /// Profile data usage
    const USAGE_PROFILE: u8 = 1;
    /// Content data usage
    const USAGE_CONTENT: u8 = 2;
    /// Social graph data usage
    const USAGE_SOCIAL_GRAPH: u8 = 3;
    
    /// Fee configuration for data monetization
    public struct FeeConfig has key, store {
        id: UID,
        // Base fee per data access
        base_fee: u64,
        // Fee per data usage type (as percentage of base fee)
        analytics_fee_bps: u64,
        profile_fee_bps: u64,
        content_fee_bps: u64,
        social_graph_fee_bps: u64,
        // Maximum discount for volume (in basis points, 1000 = 10%)
        max_volume_discount_bps: u64,
        // Fee tiers
        basic_fee: u64,
        standard_fee: u64,
        premium_fee: u64,
        // Fee split percentages
        user_share: u64,
        platform_share: u64,
        mysocial_share: u64,
    }
    
    // === Monetization Levels ===
    /// Basic data monetization (public analytics only)
    const MONETIZATION_BASIC: u8 = 0;
    /// Standard data monetization (profile data, content engagement)
    const MONETIZATION_STANDARD: u8 = 1;
    /// Premium data monetization (comprehensive data access)
    const MONETIZATION_PREMIUM: u8 = 2;
    
    // === Fee Model Names ===
    /// Name for basic data usage fee model
    const FEE_MODEL_BASIC: vector<u8> = b"AI_Data_Basic";
    /// Name for standard data usage fee model
    const FEE_MODEL_STANDARD: vector<u8> = b"AI_Data_Standard";
    /// Name for premium data usage fee model
    const FEE_MODEL_PREMIUM: vector<u8> = b"AI_Data_Premium";
    
    // === Default Fee Amounts ===
    /// Default fee for basic data usage (in MYS tokens)
    const DEFAULT_BASIC_FEE: u64 = 10;
    /// Default fee for standard data usage (in MYS tokens)
    const DEFAULT_STANDARD_FEE: u64 = 50;
    /// Default fee for premium data usage (in MYS tokens)
    const DEFAULT_PREMIUM_FEE: u64 = 100;
    
    // === Default Revenue Shares (in basis points) ===
    /// Default user share percentage (50%)
    const DEFAULT_USER_SHARE: u64 = 5000; // 50%
    /// Default platform share percentage (30%)
    const DEFAULT_PLATFORM_SHARE: u64 = 3000; // 30%
    /// Default MySocial share percentage (20%)
    const DEFAULT_MYSOCIAL_SHARE: u64 = 2000; // 20%
    
    // === Structs ==="
    
    /// AI Data Monetization Manager
    public struct DataMonetizationManager has key {
        id: UID,
        /// Map from profile ID to monetization settings
        profile_settings: Table<ID, ProfileMonetizationSettings>,
        /// Map from platform ID to platform treasury
        platform_treasuries: Table<ID, PlatformTreasury>,
        /// Map from agent ID to payment record
        agent_payments: Table<ID, AgentPaymentRecord>,
        /// Map from agent ID to fee override
        agent_fee_overrides: Table<ID, AgentFeeOverride>,
        /// Total earnings across all users
        total_earnings: u64,
    }
    
    /// Profile monetization settings
    public struct ProfileMonetizationSettings has store, drop {
        /// Profile ID
        profile_id: ID,
        /// Monetization enabled
        monetization_enabled: bool,
        /// Monetization level
        monetization_level: u8,
        /// Allowed data usage types
        allowed_usage_types: vector<u8>,
        /// Revenue earned (not yet withdrawn)
        earned_revenue: u64,
        /// Total all-time earnings
        total_earnings: u64,
        /// Last updated timestamp
        last_updated: u64,
    }
    
    /// Platform treasury for data monetization
    public struct PlatformTreasury has store {
        /// Platform ID
        platform_id: ID,
        /// Balance for platform's share
        balance: Balance<MYS>,
        /// Total earnings
        total_earnings: u64,
    }
    
    /// Agent payment record
    public struct AgentPaymentRecord has store, drop {
        /// Agent ID
        agent_id: ID,
        /// Total payments made
        total_payments: u64,
        /// Count of data usages paid for
        usage_count: u64,
        /// Last payment timestamp
        last_payment: u64,
    }
    
    /// Fee override for a specific agent
    public struct AgentFeeOverride has store, drop {
        /// Agent ID
        agent_id: ID,
        /// Basic usage fee override
        basic_fee: u64,
        /// Standard usage fee override
        standard_fee: u64,
        /// Premium usage fee override
        premium_fee: u64,
        /// Custom user share percentage
        user_share: u64,
        /// Custom platform share percentage
        platform_share: u64,
        /// Custom MySocial share percentage
        mysocial_share: u64,
    }
    
    /// User's data usage authorization token
    public struct DataUsageAuthorization has key, store {
        id: UID,
        /// Profile that authorized the data usage
        profile_id: ID,
        /// Agent authorized to use the data
        agent_id: ID,
        /// Platform where the data will be used
        platform_id: ID,
        /// Monetization level of the authorization
        monetization_level: u8,
        /// Allowed data usage types
        allowed_usage_types: vector<u8>,
        /// Payment amount for this authorization
        payment_amount: u64,
        /// When the authorization was created
        creation_timestamp: u64,
        /// When the authorization expires
        expiration_timestamp: u64,
    }
    
    /// Get the profile ID from a data usage authorization
    public fun get_auth_profile_id(auth: &DataUsageAuthorization): ID {
        auth.profile_id
    }
    
    /// Get the agent ID from a data usage authorization
    public fun get_auth_agent_id(auth: &DataUsageAuthorization): ID {
        auth.agent_id
    }
    
    /// Get the platform ID from a data usage authorization
    public fun get_auth_platform_id(auth: &DataUsageAuthorization): ID {
        auth.platform_id
    }
    
    /// Get the expiration timestamp from a data usage authorization
    public fun get_auth_expiration_timestamp(auth: &DataUsageAuthorization): u64 {
        auth.expiration_timestamp
    }
    
    /// Get the monetization level from a data usage authorization
    public fun get_auth_monetization_level(auth: &DataUsageAuthorization): u8 {
        auth.monetization_level
    }
    
    /// Get the allowed usage types from a data usage authorization
    public fun get_auth_allowed_usage_types(auth: &DataUsageAuthorization): vector<u8> {
        auth.allowed_usage_types
    }
    
    // === Events ===
    
    /// Event emitted when a user opts in for data monetization
    public struct DataMonetizationOptInEvent has copy, drop {
        profile_id: ID,
        monetization_level: u8,
        allowed_usage_types: vector<u8>,
        timestamp: u64,
    }
    
    /// Event emitted when an agent pays for data usage
    public struct DataUsagePaymentEvent has copy, drop {
        agent_id: ID,
        platform_id: ID,
        profile_id: ID,
        usage_type: u8,
        monetization_level: u8,
        payment_amount: u64,
        user_share: u64,
        platform_share: u64,
        mysocial_share: u64,
        timestamp: u64,
    }
    
    /// Event emitted when a user withdraws their earnings
    public struct EarningsWithdrawalEvent has copy, drop {
        profile_id: ID,
        amount: u64,
        recipient: address,
        timestamp: u64,
    }
    
    // === Initialization ===
    
    /// Initialize the AI Data Monetization system
    fun init(ctx: &mut TxContext) {
        // Create and share data monetization manager
        transfer::share_object(
            DataMonetizationManager {
                id: object::new(ctx),
                profile_settings: table::new(ctx),
                platform_treasuries: table::new(ctx),
                agent_payments: table::new(ctx),
                agent_fee_overrides: table::new(ctx),
                total_earnings: 0,
            }
        );
    }
    
    /// Initialize AI Data Monetization fee models in the universal fee distribution system
    /// This should be called during system initialization after fee_distribution is initialized
    public entry fun initialize_fee_models(
        admin_cap: &fee_distribution::AdminCap,
        registry: &mut fee_distribution::FeeRegistry,
        ctx: &mut TxContext
    ) {
        // Recipient addresses
        let recipient_addresses = vector[
            // User representative address (placeholder - in real usage this will be dynamic)
            @0x0,
            // Platform representative address
            tx_context::sender(ctx),
            // MySocial treasury address
            tx_context::sender(ctx)
        ];
        
        // Recipient names
        let recipient_names = vector[
            string::utf8(b"User"),
            string::utf8(b"Platform"),
            string::utf8(b"MySocial Treasury")
        ];
        
        // Recipient shares (in basis points)
        let recipient_shares = vector[
            DEFAULT_USER_SHARE,
            DEFAULT_PLATFORM_SHARE,
            DEFAULT_MYSOCIAL_SHARE
        ];
        
        // Create fee model for basic data usage
        fee_distribution::create_fixed_fee_model(
            admin_cap,
            registry,
            string::utf8(FEE_MODEL_BASIC),
            string::utf8(b"Fee for basic AI data usage"),
            DEFAULT_BASIC_FEE * 100000000, // Convert to smallest units
            recipient_addresses,
            recipient_names,
            recipient_shares,
            tx_context::sender(ctx), // Owner (admin)
            ctx
        );
        
        // Create fee model for standard data usage
        fee_distribution::create_fixed_fee_model(
            admin_cap,
            registry,
            string::utf8(FEE_MODEL_STANDARD),
            string::utf8(b"Fee for standard AI data usage"),
            DEFAULT_STANDARD_FEE * 100000000, // Convert to smallest units
            recipient_addresses,
            recipient_names,
            recipient_shares,
            tx_context::sender(ctx), // Owner (admin)
            ctx
        );
        
        // Create fee model for premium data usage
        fee_distribution::create_fixed_fee_model(
            admin_cap,
            registry,
            string::utf8(FEE_MODEL_PREMIUM),
            string::utf8(b"Fee for premium AI data usage"),
            DEFAULT_PREMIUM_FEE * 100000000, // Convert to smallest units
            recipient_addresses,
            recipient_names,
            recipient_shares,
            tx_context::sender(ctx), // Owner (admin)
            ctx
        );
    }
    
    // === Monetization Settings ===
    
    /// Opt in for data monetization
    public entry fun opt_in_for_monetization(
        manager: &mut DataMonetizationManager,
        profile: &Profile,
        monetization_level: u8,
        allowed_usage_types: vector<u8>,
        ctx: &mut TxContext
    ) {
        // Verify caller owns the profile
        assert!(profile::owner(profile) == tx_context::sender(ctx), EUnauthorized);
        
        // Verify monetization level is valid
        assert!(
            monetization_level == MONETIZATION_BASIC ||
            monetization_level == MONETIZATION_STANDARD ||
            monetization_level == MONETIZATION_PREMIUM,
            EInvalidFeeConfig
        );
        
        let profile_id = object::id(profile);
        
        // Create settings
        let settings = ProfileMonetizationSettings {
            profile_id,
            monetization_enabled: true,
            monetization_level,
            allowed_usage_types,
            earned_revenue: 0,
            total_earnings: 0,
            last_updated: tx_context::epoch_timestamp_ms(ctx),
        };
        
        // Add or update settings
        if (table::contains(&manager.profile_settings, profile_id)) {
            let existing_settings = table::borrow_mut(&mut manager.profile_settings, profile_id);
            
            // Preserve earnings when updating settings
            let earned_revenue = existing_settings.earned_revenue;
            let total_earnings = existing_settings.total_earnings;
            
            *existing_settings = settings;
            existing_settings.earned_revenue = earned_revenue;
            existing_settings.total_earnings = total_earnings;
        } else {
            table::add(&mut manager.profile_settings, profile_id, settings);
        };
        
        // Emit event
        event::emit(DataMonetizationOptInEvent {
            profile_id,
            monetization_level,
            allowed_usage_types,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }
    
    /// Opt out from data monetization
    public entry fun opt_out_from_monetization(
        manager: &mut DataMonetizationManager,
        profile: &Profile,
        ctx: &mut TxContext
    ) {
        // Verify caller owns the profile
        assert!(profile::owner(profile) == tx_context::sender(ctx), EUnauthorized);
        
        let profile_id = object::id(profile);
        
        // Verify profile has monetization settings
        assert!(table::contains(&manager.profile_settings, profile_id), EUserNotOptedIn);
        
        // Get settings and disable monetization
        let settings = table::borrow_mut(&mut manager.profile_settings, profile_id);
        settings.monetization_enabled = false;
        settings.last_updated = tx_context::epoch_timestamp_ms(ctx);
    }
    
    // === Agent Payment ===
    
    /// Pay for data usage using the universal fee distribution system
    public entry fun pay_for_data_usage(
        manager: &mut DataMonetizationManager,
        fee_registry: &mut FeeRegistry,
        agent_cap: &AgentCap,
        platform_id: ID,
        profile_id: ID,
        usage_type: u8,
        payment: &mut Coin<MYS>,
        duration_hours: u64,
        ctx: &mut TxContext
    ) {
        let agent_id = ai_agent_mpc::get_agent_id(agent_cap);
        // Verify profile has opted in for monetization
        assert!(table::contains(&manager.profile_settings, profile_id), EUserNotOptedIn);
        let profile_settings = table::borrow(&manager.profile_settings, profile_id);
        assert!(profile_settings.monetization_enabled, EUserNotOptedIn);
        
        // Verify usage type is allowed for this profile
        assert!(vector::contains(&profile_settings.allowed_usage_types, &usage_type), EUserNotOptedIn);
        
        // Determine which fee model to use based on monetization level
        let fee_model_name = if (profile_settings.monetization_level == MONETIZATION_BASIC) {
            string::utf8(FEE_MODEL_BASIC)
        } else if (profile_settings.monetization_level == MONETIZATION_STANDARD) {
            string::utf8(FEE_MODEL_STANDARD)
        } else {
            string::utf8(FEE_MODEL_PREMIUM)
        };
        
        // Look up fee model ID
        let (exists, fee_model_id) = fee_distribution::find_fee_model_by_name(
            fee_registry,
            fee_model_name
        );
        assert!(exists, EInvalidFeeConfig);
        
        // Process the payment through fee distribution system
        // The system will extract the correct fee and distribute it to recipients
        let transaction_amount = coin::value(payment);
        let fee_amount = fee_distribution::collect_and_distribute_fees<MYS>(
            fee_registry,
            fee_model_id,
            transaction_amount,
            payment,
            ctx
        );
        
        // Update agent payment record
        if (!table::contains(&manager.agent_payments, agent_id)) {
            table::add(
                &mut manager.agent_payments,
                agent_id,
                AgentPaymentRecord {
                    agent_id,
                    total_payments: 0,
                    usage_count: 0,
                    last_payment: 0,
                }
            );
        };
        let payment_record = table::borrow_mut(&mut manager.agent_payments, agent_id);
        payment_record.total_payments = payment_record.total_payments + fee_amount;
        payment_record.usage_count = payment_record.usage_count + 1;
        payment_record.last_payment = tx_context::epoch_timestamp_ms(ctx);
        
        // Update total earnings for stats
        manager.total_earnings = manager.total_earnings + fee_amount;
        
        // Create data usage authorization token
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        let expiration_time = current_time + (duration_hours * 3600000); // Convert hours to milliseconds
        
        let authorization = DataUsageAuthorization {
            id: object::new(ctx),
            profile_id,
            agent_id,
            platform_id,
            monetization_level: profile_settings.monetization_level,
            allowed_usage_types: profile_settings.allowed_usage_types,
            payment_amount: fee_amount,
            creation_timestamp: current_time,
            expiration_timestamp: expiration_time,
        };
        
        // Emit legacy event for compatibility
        // Get the fee model info to extract shares
        let (_, _, _, _, total_split_bps) = fee_distribution::get_fee_model_info(
            fee_registry,
            fee_model_id
        );
        let splits = fee_distribution::get_fee_splits(fee_registry, fee_model_id);
        
        // Default share values if we can't extract them
        let mut user_share = DEFAULT_USER_SHARE;
        let mut platform_share = DEFAULT_PLATFORM_SHARE;
        let mut mysocial_share = DEFAULT_MYSOCIAL_SHARE;
        
        // Try to extract shares from fee model
        let mut i = 0;
        let len = vector::length(&splits);
        while (i < len) {
            let split = vector::borrow(&splits, i);
            if (i == 0) { // Assuming first split is for user
                user_share = fee_distribution::get_fee_split_share_bps(split);
            } else if (i == 1) { // Assuming second split is for platform
                platform_share = fee_distribution::get_fee_split_share_bps(split);
            } else if (i == 2) { // Assuming third split is for MySocial
                mysocial_share = fee_distribution::get_fee_split_share_bps(split);
            };
            i = i + 1;
        };
        
        // Calculate approximate share amounts for the event
        let user_amount = (fee_amount * user_share) / 10000;
        let platform_amount = (fee_amount * platform_share) / 10000;
        let mysocial_amount = fee_amount - user_amount - platform_amount;
        
        event::emit(DataUsagePaymentEvent {
            agent_id,
            platform_id,
            profile_id,
            usage_type,
            monetization_level: profile_settings.monetization_level,
            payment_amount: fee_amount,
            user_share: user_amount,
            platform_share: platform_amount,
            mysocial_share: mysocial_amount,
            timestamp: current_time,
        });
        
        // Transfer authorization to agent owner
        transfer::transfer(authorization, tx_context::sender(ctx));
    }
    
    // === Earnings Withdrawal ===
    
    /// Withdraw user earnings - PLACEHOLDER IMPLEMENTATION
    /// This is a stub implementation that needs proper implementation for production use
    /// WARNING: This implementation does not actually create or transfer coins
    #[allow(lint(coin_field_not_tracked))]
    public entry fun withdraw_user_earnings(
        manager: &mut DataMonetizationManager,
        profile: &Profile,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Verify caller owns the profile
        assert!(profile::owner(profile) == tx_context::sender(ctx), EUnauthorized);
        
        let profile_id = object::id(profile);
        
        // Verify profile has monetization settings
        assert!(table::contains(&manager.profile_settings, profile_id), EUserNotOptedIn);
        
        let settings = table::borrow_mut(&mut manager.profile_settings, profile_id);
        
        // Verify sufficient balance
        assert!(settings.earned_revenue >= amount, EWithdrawalExceedsBalance);
        
        // Deduct from earned revenue
        settings.earned_revenue = settings.earned_revenue - amount;
        
        // PLACEHOLDER: In a real implementation, we would create and transfer coins
        // This would use a proper balance source and coin creation pattern
        
        // Emit event
        event::emit(EarningsWithdrawalEvent {
            profile_id,
            amount,
            recipient: profile::owner(profile),
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }
    
    /// Withdraw platform earnings
    public entry fun withdraw_platform_earnings(
        manager: &mut DataMonetizationManager,
        platform: &Platform,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform owner
        assert!(platform::owner(platform) == tx_context::sender(ctx), EUnauthorized);
        
        let platform_id = object::id(platform);
        
        // Verify platform has a treasury
        assert!(table::contains(&manager.platform_treasuries, platform_id), EInvalidFeeConfig);
        
        let platform_treasury = table::borrow_mut(&mut manager.platform_treasuries, platform_id);
        
        // Verify sufficient balance
        assert!(balance::value(&platform_treasury.balance) >= amount, EWithdrawalExceedsBalance);
        
        // Create coin from balance
        let withdraw_balance = balance::split(&mut platform_treasury.balance, amount);
        let coin = coin::from_balance(withdraw_balance, ctx);
        
        // Transfer to platform owner
        transfer::public_transfer(coin, platform::owner(platform));
    }
    
    // === Admin Functions ===
    
    /// Update fee configuration
    public entry fun update_fee_config(
        fee_config: &mut FeeConfig,
        basic_fee: u64,
        standard_fee: u64,
        premium_fee: u64,
        user_share: u64,
        platform_share: u64,
        mysocial_share: u64,
        ctx: &mut TxContext
    ) {
        // In a real implementation, we would verify the caller has admin privileges
        // Here, we're assuming the caller is authorized
        
        // Verify shares add up to 100%
        assert!(user_share + platform_share + mysocial_share == 100, EInvalidFeeConfig);
        
        // Update fee configuration
        fee_config.basic_fee = basic_fee;
        fee_config.standard_fee = standard_fee;
        fee_config.premium_fee = premium_fee;
        fee_config.user_share = user_share;
        fee_config.platform_share = platform_share;
        fee_config.mysocial_share = mysocial_share;
    }
    
    /// Set agent fee override
    public entry fun set_agent_fee_override(
        manager: &mut DataMonetizationManager,
        agent_cap: &AgentCap,
        basic_fee: u64,
        standard_fee: u64,
        premium_fee: u64,
        user_share: u64,
        platform_share: u64,
        mysocial_share: u64,
        ctx: &mut TxContext
    ) {
        // Verify caller owns the agent
        assert!(ai_agent_mpc::get_agent_owner(agent_cap) == tx_context::sender(ctx), EUnauthorized);
        
        let agent_id = ai_agent_mpc::get_agent_id(agent_cap);
        
        // Verify shares add up to 100%
        assert!(user_share + platform_share + mysocial_share == 100, EInvalidFeeConfig);
        
        // Create or update fee override
        let fee_override = AgentFeeOverride {
            agent_id,
            basic_fee,
            standard_fee,
            premium_fee,
            user_share,
            platform_share,
            mysocial_share,
        };
        
        if (table::contains(&manager.agent_fee_overrides, agent_id)) {
            let existing_override = table::borrow_mut(&mut manager.agent_fee_overrides, agent_id);
            *existing_override = fee_override;
        } else {
            table::add(&mut manager.agent_fee_overrides, agent_id, fee_override);
        };
    }
    
    // === Public Accessor Functions ===
    
    /// Check if a profile has opted in for monetization
    public fun is_monetization_enabled(
        manager: &DataMonetizationManager,
        profile_id: ID
    ): bool {
        if (!table::contains(&manager.profile_settings, profile_id)) {
            return false
        };
        
        table::borrow(&manager.profile_settings, profile_id).monetization_enabled
    }
    
    /// Get profile monetization settings
    public fun get_profile_monetization_settings(
        manager: &DataMonetizationManager,
        profile_id: ID
    ): (bool, bool, u8, vector<u8>, u64, u64) {
        if (!table::contains(&manager.profile_settings, profile_id)) {
            return (false, false, 0, vector::empty(), 0, 0)
        };
        
        let settings = table::borrow(&manager.profile_settings, profile_id);
        (
            true,
            settings.monetization_enabled,
            settings.monetization_level,
            settings.allowed_usage_types,
            settings.earned_revenue,
            settings.total_earnings
        )
    }
    
    /// Get agent payment record
    public fun get_agent_payment_record(
        manager: &DataMonetizationManager,
        agent_id: ID
    ): (bool, u64, u64, u64) {
        if (!table::contains(&manager.agent_payments, agent_id)) {
            return (false, 0, 0, 0)
        };
        
        let record = table::borrow(&manager.agent_payments, agent_id);
        (
            true,
            record.total_payments,
            record.usage_count,
            record.last_payment
        )
    }
    
    /// Get platform treasury info
    public fun get_platform_treasury_info(
        manager: &DataMonetizationManager,
        platform_id: ID
    ): (bool, u64, u64) {
        if (!table::contains(&manager.platform_treasuries, platform_id)) {
            return (false, 0, 0)
        };
        
        let treasury = table::borrow(&manager.platform_treasuries, platform_id);
        (
            true,
            balance::value(&treasury.balance),
            treasury.total_earnings
        )
    }
    
    /// Get fee for data usage
    public fun get_data_usage_fee(
        manager: &DataMonetizationManager,
        fee_config: &FeeConfig,
        agent_id: ID,
        monetization_level: u8
    ): u64 {
        if (table::contains(&manager.agent_fee_overrides, agent_id)) {
            // Use agent-specific fee override
            let fee_override = table::borrow(&manager.agent_fee_overrides, agent_id);
            if (monetization_level == MONETIZATION_BASIC) {
                fee_override.basic_fee
            } else if (monetization_level == MONETIZATION_STANDARD) {
                fee_override.standard_fee
            } else {
                fee_override.premium_fee
            }
        } else {
            // Use default fees from config
            if (monetization_level == MONETIZATION_BASIC) {
                fee_config.basic_fee
            } else if (monetization_level == MONETIZATION_STANDARD) {
                fee_config.standard_fee
            } else {
                fee_config.premium_fee
            }
        }
    }
    
    // === Monetization Constants ===
    
    /// Get basic monetization level constant
    public fun basic_monetization_level(): u8 {
        MONETIZATION_BASIC
    }
    
    /// Get standard monetization level constant
    public fun standard_monetization_level(): u8 {
        MONETIZATION_STANDARD
    }
    
    /// Get premium monetization level constant
    public fun premium_monetization_level(): u8 {
        MONETIZATION_PREMIUM
    }
    
    /// Get analytics usage type constant
    public fun analytics_usage_type(): u8 {
        USAGE_ANALYTICS
    }
    
    /// Get profile data usage type constant
    public fun profile_usage_type(): u8 {
        USAGE_PROFILE
    }
    
    /// Get content data usage type constant
    public fun content_usage_type(): u8 {
        USAGE_CONTENT
    }
    
    /// Get social graph data usage type constant
    public fun social_graph_usage_type(): u8 {
        USAGE_SOCIAL_GRAPH
    }
}