// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Platform module for the MySocial network
/// Manages social media platforms and their timelines
module social_contracts::platform {
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    
    use mys::object::{Self, UID, ID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer;
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::balance::{Self, Balance};
    use mys::mys::MYS;
    use mys::url::{Self, Url};
    use mys::dynamic_field;
    use mys::vec_set::{Self, VecSet};
    
    use social_contracts::profile::{Self, Profile};
    use social_contracts::reputation;
    use social_contracts::post::{Self, Post};

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EPlatformNotFound: u64 = 1;
    const EPlatformAlreadyExists: u64 = 2;
    const EInvalidTokenAmount: u64 = 3;
    const EInsufficientTokens: u64 = 4;
    const EPostAlreadyInTimeline: u64 = 5;
    const EPostNotInTimeline: u64 = 6;

    /// Field names for dynamic fields
    const MODERATORS_FIELD: vector<u8> = b"moderators";
    const POST_IDS_FIELD: vector<u8> = b"post_ids";
    const BLOCKED_PROFILES_FIELD: vector<u8> = b"blocked_profiles";

    /// Platform object that contains information about a social media platform
    public struct Platform has key {
        id: UID,
        /// Platform name
        name: String,
        /// Platform description
        description: String,
        /// Platform logo URL
        logo: Option<Url>,
        /// Platform owner address
        owner: address,
        /// Creation timestamp
        created_at: u64,
        /// Platform-specific tokens treasury
        treasury: Balance<MYS>,
    }

    /// Platform registry that keeps track of all platforms
    public struct PlatformRegistry has key {
        id: UID,
        /// Table mapping platform names to platform IDs
        platforms_by_name: Table<String, address>,
        /// Table mapping owner addresses to their platforms
        platforms_by_owner: Table<address, vector<address>>,
    }

    /// Timeline object for a platform
    public struct Timeline has key {
        id: UID,
        /// Platform ID this timeline belongs to
        platform_id: address,
        /// Number of posts in the timeline
        post_count: u64,
    }

    /// Platform created event
    public struct PlatformCreatedEvent has copy, drop {
        platform_id: address,
        name: String,
        owner: address,
    }

    /// Platform token created event
    public struct PlatformTokenCreatedEvent has copy, drop {
        platform_id: address,
        name: String,
        ticker: String,
        supply: u64,
    }

    /// Platform token supply changed event
    public struct TokenSupplyChangedEvent has copy, drop {
        platform_id: address,
        old_supply: u64,
        new_supply: u64,
        change_amount: u64,
        is_mint: bool,
    }

    /// Post added to timeline event
    public struct PostAddedToTimelineEvent has copy, drop {
        platform_id: address,
        post_id: address,
        added_by: address,
    }

    /// Post removed from timeline event
    public struct PostRemovedFromTimelineEvent has copy, drop {
        platform_id: address,
        post_id: address,
        removed_by: address,
    }

    /// Create and share the global platform registry
    /// This should be called once during system initialization
    public fun initialize(ctx: &mut TxContext) {
        let registry = PlatformRegistry {
            id: object::new(ctx),
            platforms_by_name: table::new(ctx),
            platforms_by_owner: table::new(ctx),
        };

        transfer::share_object(registry);
    }

    /// Create a new platform
    public fun create_platform(
        registry: &mut PlatformRegistry,
        name: String,
        description: String,
        logo_url: Option<vector<u8>>,
        ctx: &mut TxContext
    ): Platform {
        let owner = tx_context::sender(ctx);
        
        // Check if platform name is already taken
        assert!(!table::contains(&registry.platforms_by_name, name), EPlatformAlreadyExists);
        
        // Convert logo URL bytes to Url if provided
        let mut logo_url_mut = logo_url;
        let logo = if (option::is_some(&logo_url_mut)) {
            let url_bytes = option::extract(&mut logo_url_mut);
            option::some(url::new_unsafe_from_bytes(url_bytes))
        } else {
            option::none()
        };
        
        let mut platform = Platform {
            id: object::new(ctx),
            name,
            description,
            logo,
            owner,
            created_at: tx_context::epoch(ctx),
            treasury: balance::zero(),
        };
        
        // Create empty moderators set
        let mut moderators = vec_set::empty<address>();
        
        // Add owner as a moderator
        vec_set::insert(&mut moderators, owner);
        
        // Add moderators as a dynamic field
        dynamic_field::add(&mut platform.id, MODERATORS_FIELD, moderators);
        
        // Register platform in registry
        let platform_id = object::uid_to_address(&platform.id);
        
        // Add to platforms by name
        table::add(&mut registry.platforms_by_name, *&platform.name, platform_id);
        
        // Add to platforms by owner
        if (!table::contains(&registry.platforms_by_owner, owner)) {
            table::add(&mut registry.platforms_by_owner, owner, vector::empty<address>());
        };
        let owner_platforms = table::borrow_mut(&mut registry.platforms_by_owner, owner);
        vector::push_back(owner_platforms, platform_id);
        
        // Create timeline for this platform
        let mut timeline = Timeline {
            id: object::new(ctx),
            platform_id,
            post_count: 0,
        };
        
        // Add empty post IDs set to timeline
        dynamic_field::add(&mut timeline.id, POST_IDS_FIELD, vec_set::empty<address>());
        
        // Share timeline object
        transfer::share_object(timeline);
        
        // Emit platform created event
        event::emit(PlatformCreatedEvent {
            platform_id,
            name: platform.name,
            owner,
        });
        
        platform
    }

    /// Create a new platform and transfer to owner
    public entry fun create_and_register_platform(
        registry: &mut PlatformRegistry,
        name: String,
        description: String,
        logo_url: vector<u8>,
        ctx: &mut TxContext
    ) {
        let logo = if (vector::length(&logo_url) > 0) {
            option::some(logo_url)
        } else {
            option::none()
        };
        
        let platform = create_platform(
            registry,
            name,
            description,
            logo,
            ctx
        );
        
        // Transfer platform to owner
        transfer::transfer(platform, tx_context::sender(ctx));
    }

    /// Add MYS tokens to platform treasury
    public entry fun add_to_treasury(
        platform: &mut Platform,
        coin: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform owner or moderator
        let caller = tx_context::sender(ctx);
        assert!(is_owner_or_moderator(platform, caller), EUnauthorized);
        
        // Check amount validity
        assert!(amount > 0 && coin::value(coin) >= amount, EInvalidTokenAmount);
        
        // Split coin and add to treasury
        let treasury_coin = coin::split(coin, amount, ctx);
        balance::join(&mut platform.treasury, coin::into_balance(treasury_coin));
    }

    /// Add a post to a platform's timeline
    public entry fun add_post_to_timeline(
        platform: &Platform,
        timeline: &mut Timeline,
        post: &Post,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform owner or moderator
        let caller = tx_context::sender(ctx);
        assert!(is_owner_or_moderator(platform, caller), EUnauthorized);
        
        // Verify timeline belongs to this platform
        let platform_id = object::uid_to_address(&platform.id);
        assert!(timeline.platform_id == platform_id, EPlatformNotFound);
        
        // Get post ID
        let post_id = object::uid_to_address(post::id(post));
        
        // Get post IDs set from timeline
        let post_ids = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut timeline.id, POST_IDS_FIELD);
        
        // Check if post is already in timeline
        assert!(!vec_set::contains(post_ids, &post_id), EPostAlreadyInTimeline);
        
        // Add post to timeline
        vec_set::insert(post_ids, post_id);
        
        // Emit post added event
        event::emit(PostAddedToTimelineEvent {
            platform_id,
            post_id,
            added_by: caller,
        });
    }

    /// Remove a post from a platform's timeline
    public entry fun remove_post_from_timeline(
        platform: &Platform,
        timeline: &mut Timeline,
        post_id: address,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform owner or moderator
        let caller = tx_context::sender(ctx);
        assert!(is_owner_or_moderator(platform, caller), EUnauthorized);
        
        // Verify timeline belongs to this platform
        let platform_id = object::uid_to_address(&platform.id);
        assert!(timeline.platform_id == platform_id, EPlatformNotFound);
        
        // Get post IDs set from timeline
        let post_ids = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut timeline.id, POST_IDS_FIELD);
        
        // Check if post is in timeline
        assert!(vec_set::contains(post_ids, &post_id), EPostNotInTimeline);
        
        // Remove post from timeline
        vec_set::remove(post_ids, &post_id);
        
        // Emit post removed event
        event::emit(PostRemovedFromTimelineEvent {
            platform_id,
            post_id,
            removed_by: caller,
        });
    }

    /// Add a moderator to a platform
    public entry fun add_moderator(
        platform: &mut Platform,
        moderator_address: address,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform owner
        assert!(platform.owner == tx_context::sender(ctx), EUnauthorized);
        
        // Get moderators set
        let moderators = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut platform.id, MODERATORS_FIELD);
        
        // Add moderator if not already a moderator
        if (!vec_set::contains(moderators, &moderator_address)) {
            vec_set::insert(moderators, moderator_address);
        };
    }

    /// Remove a moderator from a platform
    public entry fun remove_moderator(
        platform: &mut Platform,
        moderator_address: address,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform owner
        assert!(platform.owner == tx_context::sender(ctx), EUnauthorized);
        
        // Cannot remove owner as moderator
        assert!(moderator_address != platform.owner, EUnauthorized);
        
        // Get moderators set
        let moderators = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut platform.id, MODERATORS_FIELD);
        
        // Remove moderator if they are a moderator
        if (vec_set::contains(moderators, &moderator_address)) {
            vec_set::remove(moderators, &moderator_address);
        };
    }

    // === Helper functions ===

    /// Check if an address is the platform owner or a moderator
    public fun is_owner_or_moderator(platform: &Platform, addr: address): bool {
        if (platform.owner == addr) {
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

    /// Get platform description
    public fun description(platform: &Platform): String {
        platform.description
    }

    /// Get platform logo URL
    public fun logo(platform: &Platform): &Option<Url> {
        &platform.logo
    }

    /// Get platform owner
    public fun owner(platform: &Platform): address {
        platform.owner
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

    /// Get platforms owned by an address
    public fun get_platforms_by_owner(registry: &PlatformRegistry, owner: address): vector<address> {
        if (!table::contains(&registry.platforms_by_owner, owner)) {
            return vector::empty()
        };
        
        *table::borrow(&registry.platforms_by_owner, owner)
    }

    /// Get posts in a timeline
    public fun get_timeline_posts(timeline: &Timeline): vector<address> {
        let post_ids = dynamic_field::borrow<vector<u8>, VecSet<address>>(&timeline.id, POST_IDS_FIELD);
        vec_set::into_keys(*post_ids)
    }

    /// Check if a post is in a timeline
    public fun is_post_in_timeline(timeline: &Timeline, post_id: address): bool {
        let post_ids = dynamic_field::borrow<vector<u8>, VecSet<address>>(&timeline.id, POST_IDS_FIELD);
        vec_set::contains(post_ids, &post_id)
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
    public fun is_profile_blocked_by_id(platform_id: address, profile_id: address): bool {
        false // Placeholder implementation (would need to borrow object by ID)
    }
}