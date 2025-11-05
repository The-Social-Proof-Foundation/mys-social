// Copyright (c) The Social Proof Foundation, LLC.
// SPDX-License-Identifier: Apache-2.0

/// Platform module for the MySocial network
/// Manages social media platforms and their timelines

#[allow(duplicate_alias, unused_use)]
module social_contracts::platform {
    use std::{string::{Self, String}, option, vector};
    
    use mys::{
        object::{Self, UID, ID},
        tx_context::{Self, TxContext},
        transfer,
        dynamic_field,
        vec_set::{Self, VecSet},
        table::{Self, Table},
        coin::{Self, Coin},
        balance::{Self, Balance},
        myso::MYSO,
        event
    };
    
    use social_contracts::profile;
    use social_contracts::governance;
    use social_contracts::upgrade;

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EPlatformAlreadyExists: u64 = 1;
    const EAlreadyBlocked: u64 = 2;
    const ENotBlocked: u64 = 3;
    const EInvalidTokenAmount: u64 = 4;
    const EAlreadyJoined: u64 = 5;
    const ENotJoined: u64 = 6;
    const EWrongVersion: u64 = 7;
    const EInsufficientTreasuryFunds: u64 = 8;
    const EEmptyRecipientsList: u64 = 9;

    /// Field names for dynamic fields
    const MODERATORS_FIELD: vector<u8> = b"moderators";
    const BLOCKED_PROFILES_FIELD: vector<u8> = b"blocked_profiles";
    const JOINED_PROFILES_FIELD: vector<u8> = b"joined_profiles";

    /// Platform status constants
    const STATUS_DEVELOPMENT: u8 = 0;
    const STATUS_ALPHA: u8 = 1;
    const STATUS_BETA: u8 = 2;
    const STATUS_LIVE: u8 = 3;
    const STATUS_MAINTENANCE: u8 = 4;
    const STATUS_SUNSET: u8 = 5;
    const STATUS_SHUTDOWN: u8 = 6;

    /// Platform status enum
    public struct PlatformStatus has copy, drop, store {
        status: u8,
    }

    /// Admin capability for Platform system management
    public struct PlatformAdminCap has key, store {
        id: UID,
    }

    /// Platform object that contains information about a social media platform
    public struct Platform has key {
        id: UID,
        /// Platform name
        name: String,
        /// Platform tagline
        tagline: String,
        /// Platform description
        description: String,
        /// Platform logo URL
        logo: String,
        /// Platform developer address
        developer: address,
        /// Platform terms of service URL
        terms_of_service: String,
        /// Platform privacy policy URL
        privacy_policy: String,
        /// Platform names
        platforms: vector<String>,
        /// Platform URLs
        links: vector<String>,
        /// Platform status
        status: PlatformStatus,
        /// Platform release date
        release_date: String,
        /// Platform shutdown date (optional)
        shutdown_date: Option<String>,
        /// Creation timestamp
        created_at: u64,
        /// Platform-specific MYSO tokens treasury
        treasury: Balance<MYSO>,
        /// Whether the platform wants DAO governance
        wants_dao_governance: bool,
        /// DAO governance configuration parameters (all optional)
        delegate_count: Option<u64>,
        delegate_term_epochs: Option<u64>,
        proposal_submission_cost: Option<u64>,
        min_on_chain_age_days: Option<u64>,
        max_votes_per_user: Option<u64>,
        quadratic_base_cost: Option<u64>,
        voting_period_epochs: Option<u64>,
        quorum_votes: Option<u64>,
        /// ID of governance registry if created
        governance_registry_id: Option<ID>,
        /// Version for upgrades
        version: u64,
    }

    /// Platform registry that keeps track of all platforms
    public struct PlatformRegistry has key {
        id: UID,
        /// Table mapping platform names to platform IDs
        platforms_by_name: Table<String, address>,
        /// Table mapping developer addresses to their platforms
        platforms_by_developer: Table<address, vector<address>>,
        /// Table mapping platform IDs to their approval status (admin-controlled)
        platform_approvals: Table<address, bool>,
        /// Version for upgrades
        version: u64,
    }

    /// Platform created event
    public struct PlatformCreatedEvent has copy, drop {
        platform_id: address,
        name: String,
        tagline: String,
        description: String,
        developer: address,
        logo: String,
        terms_of_service: String,
        privacy_policy: String,
        platforms: vector<String>,
        links: vector<String>,
        status: PlatformStatus,
        release_date: String,
    }

    /// Platform updated event
    public struct PlatformUpdatedEvent has copy, drop {
        platform_id: address,
        name: String,
        tagline: String,
        description: String,
        terms_of_service: String,
        privacy_policy: String,
        platforms: vector<String>,
        links: vector<String>,
        status: PlatformStatus,
        release_date: String,
        shutdown_date: Option<String>,
        updated_at: u64,
    }

    /// Profile blocked by platform event
    public struct PlatformBlockedProfileEvent has copy, drop {
        platform_id: address,
        profile_id: address,
        blocked_by: address,
    }

    /// Profile unblocked by platform event
    public struct PlatformUnblockedProfileEvent has copy, drop {
        platform_id: address,
        profile_id: address,
        unblocked_by: address,
    }

    /// Moderator added event
    public struct ModeratorAddedEvent has copy, drop {
        platform_id: address,
        moderator_address: address,
        added_by: address,
    }

    /// Moderator removed event
    public struct ModeratorRemovedEvent has copy, drop {
        platform_id: address,
        moderator_address: address,
        removed_by: address,
    }

    /// Platform approval status changed event
    public struct PlatformApprovalChangedEvent has copy, drop {
        platform_id: address,
        approved: bool,
        changed_by: address,
    }

    /// Event emitted when a user joins a platform
    public struct UserJoinedPlatformEvent has copy, drop {
        profile_id: ID,
        platform_id: ID,
        user: address,
        timestamp: u64,
    }

    /// Event emitted when a user leaves a platform
    public struct UserLeftPlatformEvent has copy, drop {
        profile_id: ID,
        platform_id: ID,
        user: address,
        timestamp: u64,
    }

    /// Event emitted when tokens are airdropped from the platform treasury
    public struct TokenAirdropEvent has copy, drop {
        platform_id: address,
        recipient: address,
        amount: u64,
        reason_code: u8,
        executed_by: address,
        timestamp: u64,
    }

    /// Bootstrap initialization function - creates the platform registry
    public(package) fun bootstrap_init(ctx: &mut TxContext) {
        let registry = PlatformRegistry {
            id: object::new(ctx),
            platforms_by_name: table::new(ctx),
            platforms_by_developer: table::new(ctx),
            platform_approvals: table::new(ctx),
            version: upgrade::current_version(),
        };

        transfer::share_object(registry);
    }

    /// Create a new platform and transfer to developer
    public entry fun create_platform(
        registry: &mut PlatformRegistry,
        name: String,
        tagline: String,
        description: String,
        logo_url: String,
        terms_of_service: String,
        privacy_policy: String,
        platforms: vector<String>,
        links: vector<String>,
        status: u8,
        release_date: String,
        wants_dao_governance: bool,
        delegate_count: Option<u64>,
        delegate_term_epochs: Option<u64>,
        proposal_submission_cost: Option<u64>,
        min_on_chain_age_days: Option<u64>,
        max_votes_per_user: Option<u64>,
        quadratic_base_cost: Option<u64>,
        voting_period_epochs: Option<u64>,
        quorum_votes: Option<u64>,
        ctx: &mut TxContext
    ) {
        // Check version compatibility
        assert!(registry.version == upgrade::current_version(), EWrongVersion);
        
        let platform_id = object::new(ctx);
        let developer = tx_context::sender(ctx);
        let now = tx_context::epoch(ctx);

        // Check if platform name is already taken
        assert!(!table::contains(&registry.platforms_by_name, name), EPlatformAlreadyExists);

        // Validate status code is one of the defined constants
        assert!(
            status == STATUS_DEVELOPMENT || 
            status == STATUS_ALPHA || 
            status == STATUS_BETA || 
            status == STATUS_LIVE || 
            status == STATUS_MAINTENANCE || 
            status == STATUS_SUNSET || 
            status == STATUS_SHUTDOWN,
            EUnauthorized
        );

        // If DAO governance is not wanted, set all governance parameters to None
        let actual_delegate_count = if (wants_dao_governance) delegate_count else option::none();
        let actual_delegate_term_epochs = if (wants_dao_governance) delegate_term_epochs else option::none();
        let actual_proposal_submission_cost = if (wants_dao_governance) proposal_submission_cost else option::none();
        let actual_min_on_chain_age_days = if (wants_dao_governance) min_on_chain_age_days else option::none();
        let actual_max_votes_per_user = if (wants_dao_governance) max_votes_per_user else option::none();
        let actual_quadratic_base_cost = if (wants_dao_governance) quadratic_base_cost else option::none();
        let actual_voting_period_epochs = if (wants_dao_governance) voting_period_epochs else option::none();
        let actual_quorum_votes = if (wants_dao_governance) quorum_votes else option::none();

        let mut platform = Platform {
            id: platform_id,
            name,
            tagline,
            description,
            logo: logo_url,
            developer,
            terms_of_service,
            privacy_policy,
            platforms,
            links,
            status: new_status(status),
            release_date,
            shutdown_date: option::none(),
            created_at: now,
            treasury: balance::zero(),
            wants_dao_governance,
            delegate_count: actual_delegate_count,
            delegate_term_epochs: actual_delegate_term_epochs,
            proposal_submission_cost: actual_proposal_submission_cost,
            min_on_chain_age_days: actual_min_on_chain_age_days,
            max_votes_per_user: actual_max_votes_per_user,
            quadratic_base_cost: actual_quadratic_base_cost,
            voting_period_epochs: actual_voting_period_epochs,
            quorum_votes: actual_quorum_votes,
            governance_registry_id: option::none(),
            version: upgrade::current_version(),
        };
        
        // Create empty moderators set
        let mut moderators = vec_set::empty<address>();
        
        // Add developer as a moderator
        vec_set::insert(&mut moderators, developer);
        
        // Add moderators as a dynamic field
        dynamic_field::add(&mut platform.id, MODERATORS_FIELD, moderators);
        
        // Register platform in registry
        let platform_id = object::uid_to_address(&platform.id);
        
        // Add to platforms by name
        table::add(&mut registry.platforms_by_name, *&platform.name, platform_id);
        
        // Add to platforms by developer
        if (!table::contains(&registry.platforms_by_developer, developer)) {
            table::add(&mut registry.platforms_by_developer, developer, vector::empty<address>());
        };
        let developer_platforms = table::borrow_mut(&mut registry.platforms_by_developer, developer);
        vector::push_back(developer_platforms, platform_id);
        
        // Add to platform approvals (starts as not approved)
        table::add(&mut registry.platform_approvals, platform_id, false);
        
        // Emit platform created event
        event::emit(PlatformCreatedEvent {
            platform_id,
            name: platform.name,
            tagline: platform.tagline,
            description: platform.description,
            developer,
            logo: platform.logo,
            terms_of_service: platform.terms_of_service,
            privacy_policy: platform.privacy_policy,
            platforms: platform.platforms,
            links: platform.links,
            status: platform.status,
            release_date: platform.release_date,
        });
        
        // If platform wants DAO governance, create governance registry immediately
        if (wants_dao_governance) {
            // Use default values if options are None
            let delegate_count = if (option::is_some(&platform.delegate_count)) {
                *option::borrow(&platform.delegate_count)
            } else {
                7 // Default value
            };
            
            let delegate_term_epochs = if (option::is_some(&platform.delegate_term_epochs)) {
                *option::borrow(&platform.delegate_term_epochs)
            } else {
                30 // Default value
            };
            
            let proposal_submission_cost = if (option::is_some(&platform.proposal_submission_cost)) {
                *option::borrow(&platform.proposal_submission_cost)
            } else {
                50_000_000 // Default value
            };
            
            let min_on_chain_age_days = if (option::is_some(&platform.min_on_chain_age_days)) {
                *option::borrow(&platform.min_on_chain_age_days)
            } else {
                7 // Default value
            };
            
            let max_votes_per_user = if (option::is_some(&platform.max_votes_per_user)) {
                *option::borrow(&platform.max_votes_per_user)
            } else {
                5 // Default value
            };
            
            let quadratic_base_cost = if (option::is_some(&platform.quadratic_base_cost)) {
                *option::borrow(&platform.quadratic_base_cost)
            } else {
                5_000_000 // Default value
            };
            
            let voting_period_epochs = if (option::is_some(&platform.voting_period_epochs)) {
                *option::borrow(&platform.voting_period_epochs)
            } else {
                3 // Default value
            };
            
            let quorum_votes = if (option::is_some(&platform.quorum_votes)) {
                *option::borrow(&platform.quorum_votes)
            } else {
                15 // Default value
            };
            
            // Create governance registry for this platform
            let registry_id = governance::create_platform_governance(
                delegate_count,
                delegate_term_epochs,
                proposal_submission_cost,
                min_on_chain_age_days,
                max_votes_per_user,
                quadratic_base_cost,
                voting_period_epochs,
                quorum_votes,
                ctx
            );
            
            // Store registry ID in the platform
            platform.governance_registry_id = option::some(registry_id);
        };
        
        // Transfer platform to developer
        transfer::transfer(platform, developer);
    }

    /// Update platform information
    public entry fun update_platform(
        platform: &mut Platform,
        new_name: String,
        new_tagline: String,
        new_description: String,
        new_logo_url: String,
        new_terms_of_service: String,
        new_privacy_policy: String,
        new_platforms: vector<String>,
        new_links: vector<String>,
        new_status: u8,
        new_release_date: String,
        new_shutdown_date: Option<String>,
        ctx: &mut TxContext
    ) {
        // Check version compatibility
        assert!(platform.version == upgrade::current_version(), EWrongVersion);
        
        let now = tx_context::epoch(ctx);

        // Verify caller is platform developer
        assert!(platform.developer == tx_context::sender(ctx), EUnauthorized);
        
        // Update platform information
        platform.name = new_name;
        platform.tagline = new_tagline;
        platform.description = new_description;
        platform.logo = new_logo_url;
        platform.terms_of_service = new_terms_of_service;
        platform.privacy_policy = new_privacy_policy;
        platform.platforms = new_platforms;
        platform.links = new_links;
        platform.status = new_status(new_status);
        platform.release_date = new_release_date;
        platform.shutdown_date = new_shutdown_date;

        // Emit platform updated event
        event::emit(PlatformUpdatedEvent {
            platform_id: object::uid_to_address(&platform.id),
            name: platform.name,
            tagline: platform.tagline,
            description: platform.description,
            terms_of_service: platform.terms_of_service,
            privacy_policy: platform.privacy_policy,
            platforms: platform.platforms,
            links: platform.links,
            status: platform.status,
            release_date: platform.release_date,
            shutdown_date: platform.shutdown_date,
            updated_at: now,
        });
    }

    /// Get the version of a platform
    public fun platform_version(platform: &Platform): u64 {
        platform.version
    }

    /// Get a mutable reference to the platform version (only for upgrade module)
    public fun borrow_platform_version_mut(platform: &mut Platform): &mut u64 {
        &mut platform.version
    }

    /// Get the version of the platform registry
    public fun registry_version(registry: &PlatformRegistry): u64 {
        registry.version
    }

    /// Get a mutable reference to the registry version (only for upgrade module)
    public fun borrow_registry_version_mut(registry: &mut PlatformRegistry): &mut u64 {
        &mut registry.version
    }

    /// Add MYSO tokens to platform treasury
    public entry fun add_to_treasury(
        platform: &mut Platform,
        coin: &mut Coin<MYSO>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform developer or moderator
        let caller = tx_context::sender(ctx);
        assert!(is_developer_or_moderator(platform, caller), EUnauthorized);
        
        // Check amount validity
        assert!(amount > 0 && coin::value(coin) >= amount, EInvalidTokenAmount);
        
        // Split coin and add to treasury
        let treasury_coin = coin::split(coin, amount, ctx);
        balance::join(&mut platform.treasury, coin::into_balance(treasury_coin));
    }

    /// Add a moderator to a platform
    public entry fun add_moderator(
        platform: &mut Platform,
        moderator_address: address,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform developer
        let caller = tx_context::sender(ctx);
        assert!(platform.developer == caller, EUnauthorized);
        
        // Get moderators set
        let moderators = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut platform.id, MODERATORS_FIELD);
        
        // Add moderator if not already a moderator
        if (!vec_set::contains(moderators, &moderator_address)) {
            vec_set::insert(moderators, moderator_address);
            
            // Emit moderator added event
            event::emit(ModeratorAddedEvent {
                platform_id: object::uid_to_address(&platform.id),
                moderator_address,
                added_by: caller,
            });
        };
    }

    /// Remove a moderator from a platform
    public entry fun remove_moderator(
        platform: &mut Platform,
        moderator_address: address,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform developer
        let caller = tx_context::sender(ctx);
        assert!(platform.developer == caller, EUnauthorized);
        
        // Cannot remove developer as moderator
        assert!(moderator_address != platform.developer, EUnauthorized);
        
        // Get moderators set
        let moderators = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut platform.id, MODERATORS_FIELD);
        
        // Remove moderator if they are a moderator
        if (vec_set::contains(moderators, &moderator_address)) {
            vec_set::remove(moderators, &moderator_address);
            
            // Emit moderator removed event
            event::emit(ModeratorRemovedEvent {
                platform_id: object::uid_to_address(&platform.id),
                moderator_address,
                removed_by: caller,
            });
        };
    }

    /// Block a profile from the platform
    public entry fun block_profile(
        platform: &mut Platform,
        profile_id: address,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform developer or moderator
        let caller = tx_context::sender(ctx);
        assert!(is_developer_or_moderator(platform, caller), EUnauthorized);
        
        // Create blocked profiles set if it doesn't exist
        if (!dynamic_field::exists_(&platform.id, BLOCKED_PROFILES_FIELD)) {
            let blocked_profiles = vec_set::empty<address>();
            dynamic_field::add(&mut platform.id, BLOCKED_PROFILES_FIELD, blocked_profiles);
        };
        
        // Get blocked profiles set
        let blocked_profiles = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut platform.id, BLOCKED_PROFILES_FIELD);
        
        // Check if already blocked and abort if true
        assert!(!vec_set::contains(blocked_profiles, &profile_id), EAlreadyBlocked);
        
        // Add profile to blocked set
        vec_set::insert(blocked_profiles, profile_id);
        
        // Emit platform-specific block event
        event::emit(PlatformBlockedProfileEvent {
            platform_id: object::uid_to_address(&platform.id),
            profile_id,
            blocked_by: caller,
        });
    }

    /// Unblock a profile from the platform
    public entry fun unblock_profile(
        platform: &mut Platform,
        profile_id: address,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform developer or moderator
        let caller = tx_context::sender(ctx);
        assert!(is_developer_or_moderator(platform, caller), EUnauthorized);
        
        // Check if blocked profiles set exists
        if (!dynamic_field::exists_(&platform.id, BLOCKED_PROFILES_FIELD)) {
            // Profile can't be blocked if there's no blocked profiles set
            abort ENotBlocked
        };
        
        // Get blocked profiles set
        let blocked_profiles = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut platform.id, BLOCKED_PROFILES_FIELD);
        
        // Check if profile is actually blocked and abort if not
        assert!(vec_set::contains(blocked_profiles, &profile_id), ENotBlocked);
        
        // Remove profile from blocked set
        vec_set::remove(blocked_profiles, &profile_id);
        
        // Emit platform-specific unblock event
        event::emit(PlatformUnblockedProfileEvent {
            platform_id: object::uid_to_address(&platform.id),
            profile_id,
            unblocked_by: caller,
        });
    }

    /// Toggle platform approval status (requires PlatformAdminCap only)
    public entry fun toggle_platform_approval(
        registry: &mut PlatformRegistry,
        platform_id: address,
        _: &PlatformAdminCap,
        ctx: &mut TxContext
    ) {
        // Check version compatibility
        assert!(registry.version == upgrade::current_version(), EWrongVersion);
        
        // Admin capability verification is handled by type system
        // Verify the platform exists in the registry
        assert!(table::contains(&registry.platform_approvals, platform_id), EUnauthorized);
        
        // Get current approval status and toggle it
        let current_approval = *table::borrow(&registry.platform_approvals, platform_id);
        let new_approval = !current_approval;
        
        // Update the approval status in the registry
        *table::borrow_mut(&mut registry.platform_approvals, platform_id) = new_approval;
        
        // Emit approval status changed event
        event::emit(PlatformApprovalChangedEvent {
            platform_id,
            approved: new_approval,
            changed_by: tx_context::sender(ctx),
        });
    }

    /// Create a new platform status
    public fun new_status(status: u8): PlatformStatus {
        // Validate the status code is one of the defined constants
        assert!(
            status == STATUS_DEVELOPMENT || 
            status == STATUS_ALPHA || 
            status == STATUS_BETA || 
            status == STATUS_LIVE || 
            status == STATUS_MAINTENANCE || 
            status == STATUS_SUNSET || 
            status == STATUS_SHUTDOWN,
            EUnauthorized
        );
        
        PlatformStatus { status }
    }
    
    /// Get the status value
    public fun status_value(status: &PlatformStatus): u8 {
        status.status
    }

    /// Join a platform - establishes initial connection between profile and platform
    /// Checks for blocks before allowing the join and verifies platform is approved
    /// Uses the caller's wallet address to find their profile for security
    public entry fun join_platform(
        profile_registry: &profile::UsernameRegistry,
        platform_registry: &PlatformRegistry,
        platform: &mut Platform,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let platform_id = object::id(platform);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Look up the caller's profile ID from registry
        let mut caller_profile_id_opt = profile::lookup_profile_by_owner(profile_registry, caller);
        assert!(option::is_some(&caller_profile_id_opt), EUnauthorized);
        
        // Extract profile ID and convert to ID type
        let profile_id_addr = option::extract(&mut caller_profile_id_opt);
        let profile_id = object::id_from_address(profile_id_addr);
        
        // Check if the platform has blocked this profile
        assert!(!is_profile_blocked(platform, profile_id_addr), EUnauthorized);
        
        // Check if the platform is approved by the contract owner (use registry)
        let platform_id_addr = object::uid_to_address(&platform.id);
        assert!(is_approved(platform_registry, platform_id_addr), EUnauthorized);
        
        // Create joined profiles set if it doesn't exist
        if (!dynamic_field::exists_(&platform.id, JOINED_PROFILES_FIELD)) {
            let joined_profiles = vec_set::empty<ID>();
            dynamic_field::add(&mut platform.id, JOINED_PROFILES_FIELD, joined_profiles);
        };
        
        // Get joined profiles set
        let joined_profiles = dynamic_field::borrow_mut<vector<u8>, VecSet<ID>>(&mut platform.id, JOINED_PROFILES_FIELD);
        
        // Check if profile is already joined to the platform
        assert!(!vec_set::contains(joined_profiles, &profile_id), EAlreadyJoined);
        
        // Add profile to joined profiles
        vec_set::insert(joined_profiles, profile_id);
        
        // Emit event
        event::emit(UserJoinedPlatformEvent {
            profile_id,
            platform_id,
            user: caller,
            timestamp: current_time,
        });
    }

    /// Leave a platform - removes the connection between profile and platform
    public entry fun leave_platform(
        registry: &profile::UsernameRegistry,
        platform: &mut Platform,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let platform_id = object::id(platform);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Look up the caller's profile ID from registry
        let mut caller_profile_id_opt = profile::lookup_profile_by_owner(registry, caller);
        assert!(option::is_some(&caller_profile_id_opt), EUnauthorized);
        
        // Extract profile ID and convert to ID type
        let profile_id_addr = option::extract(&mut caller_profile_id_opt);
        let profile_id = object::id_from_address(profile_id_addr);
        
        // Check if joined profiles set exists
        assert!(dynamic_field::exists_(&platform.id, JOINED_PROFILES_FIELD), ENotJoined);
        
        // Get joined profiles set
        let joined_profiles = dynamic_field::borrow_mut<vector<u8>, VecSet<ID>>(&mut platform.id, JOINED_PROFILES_FIELD);
        
        // Check if profile is a member of the platform
        assert!(vec_set::contains(joined_profiles, &profile_id), ENotJoined);
        
        // Remove profile from joined profiles
        vec_set::remove(joined_profiles, &profile_id);
        
        // Emit event
        event::emit(UserLeftPlatformEvent {
            profile_id,
            platform_id,
            user: caller,
            timestamp: current_time,
        });
    }

    /// Get platform approval status from registry
    public fun is_approved(registry: &PlatformRegistry, platform_id: address): bool {
        if (!table::contains(&registry.platform_approvals, platform_id)) {
            return false
        };
        *table::borrow(&registry.platform_approvals, platform_id)
    }

    /// Check if a profile has joined a platform
    public fun has_joined_platform(platform: &Platform, profile_id: ID): bool {
        if (!dynamic_field::exists_(&platform.id, JOINED_PROFILES_FIELD)) {
            return false
        };
        
        let joined_profiles = dynamic_field::borrow<vector<u8>, VecSet<ID>>(&platform.id, JOINED_PROFILES_FIELD);
        vec_set::contains(joined_profiles, &profile_id)
    }

    // === Helper functions ===

    /// Check if an address is the platform developer or a moderator
    public fun is_developer_or_moderator(platform: &Platform, addr: address): bool {
        if (platform.developer == addr) {
            return true
        };
        
        let moderators = dynamic_field::borrow<vector<u8>, VecSet<address>>(&platform.id, MODERATORS_FIELD);
        vec_set::contains(moderators, &addr)
    }

    // === Getters ===

    /// Get platform name
    public fun name(platform: &Platform): String {
        platform.name
    }

    /// Get platform tagline
    public fun tagline(platform: &Platform): String {
        platform.tagline
    }

    /// Get platform description
    public fun description(platform: &Platform): String {
        platform.description
    }

    /// Get platform logo URL
    public fun logo(platform: &Platform): &String {
        &platform.logo
    }

    /// Get platform developer
    public fun developer(platform: &Platform): address {
        platform.developer
    }

    /// Get platform terms of service
    public fun terms_of_service(platform: &Platform): String {
        platform.terms_of_service
    }

    /// Get platform privacy policy
    public fun privacy_policy(platform: &Platform): String {
        platform.privacy_policy
    }

    /// Get platform platforms
    public fun get_platforms(platform: &Platform): &vector<String> {
        &platform.platforms
    }

    /// Get platform links
    public fun get_links(platform: &Platform): &vector<String> {
        &platform.links
    }

    /// Get platform status
    public fun status(platform: &Platform): u8 {
        status_value(&platform.status)
    }

    /// Get platform release date
    public fun release_date(platform: &Platform): String {
        platform.release_date
    }

    /// Get platform shutdown date
    public fun shutdown_date(platform: &Platform): &Option<String> {
        &platform.shutdown_date
    }

    /// Get platform creation timestamp
    public fun created_at(platform: &Platform): u64 {
        platform.created_at
    }

    /// Get platform treasury balance
    public fun treasury_balance(platform: &Platform): u64 {
        balance::value(&platform.treasury)
    }

    /// Get platform ID
    public fun id(platform: &Platform): &UID {
        &platform.id
    }

    /// Check if an address is a moderator
    public fun is_moderator(platform: &Platform, addr: address): bool {
        let moderators = dynamic_field::borrow<vector<u8>, VecSet<address>>(&platform.id, MODERATORS_FIELD);
        vec_set::contains(moderators, &addr)
    }

    /// Get the list of moderators for a platform
    public fun get_moderators(platform: &Platform): vector<address> {
        let moderators = dynamic_field::borrow<vector<u8>, VecSet<address>>(&platform.id, MODERATORS_FIELD);
        vec_set::into_keys(*moderators)
    }

    /// Get platform by name from registry
    public fun get_platform_by_name(registry: &PlatformRegistry, name: String): Option<address> {
        if (!table::contains(&registry.platforms_by_name, name)) {
            return option::none()
        };
        
        option::some(*table::borrow(&registry.platforms_by_name, name))
    }

    /// Get platforms owned by a developer
    public fun get_platforms_by_developer(registry: &PlatformRegistry, developer: address): vector<address> {
        if (!table::contains(&registry.platforms_by_developer, developer)) {
            return vector::empty()
        };
        
        *table::borrow(&registry.platforms_by_developer, developer)
    }

    /// Check if a profile is blocked in a platform
    public fun is_profile_blocked(platform: &Platform, profile_id: address): bool {
        if (!dynamic_field::exists_(&platform.id, BLOCKED_PROFILES_FIELD)) {
            return false
        };
        
        let blocked_profiles = dynamic_field::borrow<vector<u8>, VecSet<address>>(&platform.id, BLOCKED_PROFILES_FIELD);
        vec_set::contains(blocked_profiles, &profile_id)
    }
    
    /// Check if a profile is blocked in a platform by ID
    public fun is_profile_blocked_by_id(_platform_id: address, _profile_id: address): bool {
        false // Placeholder implementation (would need to borrow object by ID)
    }

    /// Get list of blocked profiles for a platform
    public fun get_blocked_profiles(platform: &Platform): vector<address> {
        if (!dynamic_field::exists_(&platform.id, BLOCKED_PROFILES_FIELD)) {
            return vector::empty()
        };
        
        let blocked_profiles = dynamic_field::borrow<vector<u8>, VecSet<address>>(&platform.id, BLOCKED_PROFILES_FIELD);
        vec_set::into_keys(*blocked_profiles)
    }

    /// Check if platform wants DAO governance
    public fun wants_dao_governance(platform: &Platform): bool {
        platform.wants_dao_governance
    }

    /// Get platform's governance registry ID if available
    public fun governance_registry_id(platform: &Platform): &Option<ID> {
        &platform.governance_registry_id
    }

    /// Get platform's governance parameters
    public fun governance_parameters(platform: &Platform): (Option<u64>, Option<u64>, Option<u64>, Option<u64>, Option<u64>, Option<u64>, Option<u64>, Option<u64>) {
        (
            platform.delegate_count,
            platform.delegate_term_epochs,
            platform.proposal_submission_cost,
            platform.min_on_chain_age_days,
            platform.max_votes_per_user,
            platform.quadratic_base_cost,
            platform.voting_period_epochs,
            platform.quorum_votes
        )
    }

    /// Airdrop tokens to multiple recipients from the platform treasury
    /// Can only be called by platform developer or moderator
    public entry fun airdrop_from_treasury(
        platform: &mut Platform,
        recipients: vector<address>,
        amount_per_recipient: u64,
        reason_code: u8,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        
        // Verify caller is platform developer or moderator
        assert!(is_developer_or_moderator(platform, caller), EUnauthorized);
        
        // Check that recipients list is not empty
        let recipients_count = vector::length(&recipients);
        assert!(recipients_count > 0, EEmptyRecipientsList);
        
        // Calculate total amount needed
        let total_amount = amount_per_recipient * recipients_count;
        
        // Verify platform treasury has enough funds
        assert!(balance::value(&platform.treasury) >= total_amount, EInsufficientTreasuryFunds);
        
        // Get current timestamp for events
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        let platform_id = object::uid_to_address(&platform.id);
        
        // Send tokens to each recipient
        let mut i = 0;
        while (i < recipients_count) {
            let recipient = *vector::borrow(&recipients, i);
            
            // Create coin from platform treasury balance
            let airdrop_coin = coin::from_balance(
                balance::split(&mut platform.treasury, amount_per_recipient), 
                ctx
            );
            
            // Transfer to recipient
            transfer::public_transfer(airdrop_coin, recipient);
            
            // Emit airdrop event for tracking
            event::emit(TokenAirdropEvent {
                platform_id,
                recipient,
                amount: amount_per_recipient,
                reason_code,
                executed_by: caller,
                timestamp: current_time,
            });
            
            i = i + 1;
        };
    }

    /// Assign a badge to a profile - can only be called by platform admin/moderator
    /// This is the primary entry point for badge assignment
    public entry fun assign_badge(
        platform: &Platform,
        profile: &mut profile::Profile,
        badge_name: String,
        badge_description: String,
        badge_image_url: String,
        badge_type: u8,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform admin or moderator
        let caller = tx_context::sender(ctx);
        assert!(is_developer_or_moderator(platform, caller), EUnauthorized);
        
        // Get platform ID
        let platform_id = object::uid_to_address(&platform.id);
        
        // Get current time
        let now = tx_context::epoch(ctx);
        
        // Create a unique badge ID
        let mut badge_id = string::utf8(b"badge_");
        string::append(&mut badge_id, badge_name);
        
        // Add the badge directly to the profile
        profile::add_badge_to_profile(
            profile,
            badge_id,
            badge_name,
            badge_description,
            badge_image_url,
            platform_id,
            now,
            caller,
            badge_type
        );
    }

    /// Revoke a badge from a profile - can only be called by platform admin/moderator
    /// This is the primary entry point for badge revocation
    public entry fun revoke_badge(
        platform: &Platform,
        profile: &mut profile::Profile,
        badge_id: String,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform admin or moderator
        let caller = tx_context::sender(ctx);
        assert!(is_developer_or_moderator(platform, caller), EUnauthorized);
        
        // Get platform ID
        let platform_id = object::uid_to_address(&platform.id);
        
        // Get current time
        let now = tx_context::epoch(ctx);
        
        // Remove the badge directly from the profile
        profile::remove_badge_from_profile(
            profile,
            &badge_id,
            platform_id,
            caller,
            now
        );
    }

    /// When adding a moderator to a platform, register them with the profile module
    public fun add_moderator_register(
        platform: &mut Platform,
        moderator_address: address,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform developer
        let caller = tx_context::sender(ctx);
        assert!(platform.developer == caller, EUnauthorized);
        
        // Get moderators set
        let moderators = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut platform.id, MODERATORS_FIELD);
        
        // Add moderator if not already a moderator
        if (!vec_set::contains(moderators, &moderator_address)) {
            vec_set::insert(moderators, moderator_address);
            
            // Emit moderator added event
            let platform_id = object::uid_to_address(&platform.id);
            event::emit(ModeratorAddedEvent {
                platform_id,
                moderator_address,
                added_by: caller,
            });
        };
    }
    
    /// When removing a moderator from a platform
    public fun remove_moderator_unregister(
        platform: &mut Platform,
        moderator_address: address,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform developer
        let caller = tx_context::sender(ctx);
        assert!(platform.developer == caller, EUnauthorized);
        
        // Cannot remove developer as moderator
        assert!(moderator_address != platform.developer, EUnauthorized);
        
        // Get moderators set
        let moderators = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut platform.id, MODERATORS_FIELD);
        
        // Remove moderator if they are a moderator
        if (vec_set::contains(moderators, &moderator_address)) {
            vec_set::remove(moderators, &moderator_address);
            
            // Emit moderator removed event
            let platform_id = object::uid_to_address(&platform.id);
            event::emit(ModeratorRemovedEvent {
                platform_id,
                moderator_address,
                removed_by: caller,
            });
        };
    }

    #[test_only]
    /// Initialize test environment for platform module
    public fun test_init(ctx: &mut TxContext) {
        let registry = PlatformRegistry {
            id: object::new(ctx),
            platforms_by_name: table::new(ctx),
            platforms_by_developer: table::new(ctx),
            platform_approvals: table::new(ctx),
            version: 1, // Set to version 1 for testing
        };

        transfer::share_object(registry);
    }
    
    #[test_only]
    /// Test helper to directly set a profile as joined to a platform
    /// Simplifies testing by bypassing the normal join flow
    public fun test_join_platform(platform: &mut Platform, profile_id: ID) {
        // Create joined profiles set if it doesn't exist
        if (!dynamic_field::exists_(&platform.id, JOINED_PROFILES_FIELD)) {
            let joined_profiles = vec_set::empty<ID>();
            dynamic_field::add(&mut platform.id, JOINED_PROFILES_FIELD, joined_profiles);
        };
        
        // Get joined profiles set
        let joined_profiles = dynamic_field::borrow_mut<vector<u8>, VecSet<ID>>(&mut platform.id, JOINED_PROFILES_FIELD);
        
        // Add profile to joined profiles
        if (!vec_set::contains(joined_profiles, &profile_id)) {
            vec_set::insert(joined_profiles, profile_id);
        };
    }

    /// Create a PlatformAdminCap for bootstrap (package visibility only)
    /// This function is only callable by other modules in the same package
    public(package) fun create_platform_admin_cap(ctx: &mut TxContext): PlatformAdminCap {
        PlatformAdminCap {
            id: object::new(ctx)
        }
    }
    
    #[test_only]
    /// Test helper to set the approval status of a platform in the registry
    public fun test_set_approval(registry: &mut PlatformRegistry, platform_id: address, approved: bool) {
        if (!table::contains(&registry.platform_approvals, platform_id)) {
            table::add(&mut registry.platform_approvals, platform_id, approved);
        } else {
            *table::borrow_mut(&mut registry.platform_approvals, platform_id) = approved;
        };
    }
}