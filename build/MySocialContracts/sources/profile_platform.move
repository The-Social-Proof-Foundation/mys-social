// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Profile-Platform integration module that tracks basic user interactions with platforms.
/// This module provides the core on-chain relationship between profiles and platforms
/// but delegates analytics and statistics tracking to off-chain indexers.
/// Includes integration with block list functionality to prevent interactions between blocked entities.
module social_contracts::profile_platform {
    use std::string::{String};
    use std::vector;
    use mys::object::{UID, ID};
    use mys::transfer;
    use mys::tx_context::TxContext;
    use mys::event;
    use mys::table::{Self, Table};
    
    use social_contracts::platform::{Self, Platform};
    use social_contracts::block_list::{Self, BlockListRegistry};
    
    // === Errors ===
    /// User does not have a profile
    const ENoProfile: u64 = 0;
    /// Platform not found
    const EPlatformNotFound: u64 = 1;
    /// Profile-platform link already exists
    const ELinkExists: u64 = 2;
    /// Profile-platform link not found
    const ELinkNotFound: u64 = 3;
    /// Unauthorized operation
    const EUnauthorized: u64 = 4;
    /// Entity is blocked
    const EEntityBlocked: u64 = 5;
    
    // === Structs ===
    
    /// Object linking a user's profile to platforms they've interacted with.
    /// This is a minimal structure that just tracks relationships without detailed analytics.
    public struct ProfilePlatformLink has key {
        id: UID,
        profile_id: ID,
        owner: address,
        // List of all platforms the user has interacted with
        platforms: vector<ID>,
        // Timestamps for when the user joined each platform
        join_timestamps: Table<ID, u64>,
        // Track the last active timestamp for each platform
        last_active: Table<ID, u64>,
    }
    
    /// Registry for profile-platform links
    public struct ProfilePlatformRegistry has key {
        id: UID,
        // Map from profile ID to link ID
        profile_links: Table<ID, ID>,
    }
    
    // === Events ===
    // Events are focused on relationship changes, not analytics
    
    /// Event emitted when a user joins a platform
    public struct UserJoinedPlatformEvent has copy, drop {
        profile_id: ID,
        platform_id: ID,
        user: address,
        timestamp: u64,
    }
    
    /// Event emitted when a user interacts with a platform
    public struct UserPlatformInteractionEvent has copy, drop {
        profile_id: ID,
        platform_id: ID,
        interaction_type: u8, // 0 = post, 1 = like, 2 = comment, 3 = share, etc.
        timestamp: u64,
    }
    
    /// Event emitted when a user's reputation changes on a platform
    public struct UserReputationChangedEvent has copy, drop {
        profile_id: ID,
        platform_id: ID,
        old_score: u64,
        new_score: u64,
        reason: String,
        timestamp: u64,
    }
    
    // === Initialization ===
    
    /// Initialize the profile-platform integration
    fun init(ctx: &mut TxContext) {
        // Create and share registry
        transfer::share_object(
            ProfilePlatformRegistry {
                id: object::new(ctx),
                profile_links: table::new(ctx),
            }
        );
    }
    
    // === Profile-Platform Link Functions ===
    
    /// Create a link between a profile and platforms
    public entry fun create_profile_link(
        profile_id: ID,
        ctx: &mut TxContext
    ) {
        // Create link object with minimal fields
        let link = ProfilePlatformLink {
            id: object::new(ctx),
            profile_id,
            owner: tx_context::sender(ctx),
            platforms: vector::empty(),
            join_timestamps: table::new(ctx),
            last_active: table::new(ctx),
        };
        
        // Transfer link to user
        transfer::transfer(link, tx_context::sender(ctx));
    }
    
    /// Get the profile ID from a link
    public fun get_profile_id(link: &ProfilePlatformLink): ID {
        link.profile_id
    }
    
    /// Register a profile-platform link in the registry
    public entry fun register_profile_link(
        registry: &mut ProfilePlatformRegistry,
        link: &ProfilePlatformLink,
        _ctx: &mut TxContext
    ) {
        let profile_id = get_profile_id(link);
        let link_id = object::id(link);
        
        // Register if not already registered
        if (!table::contains(&registry.profile_links, profile_id)) {
            table::add(&mut registry.profile_links, profile_id, link_id);
        } else {
            let stored_link_id = table::borrow_mut(&mut registry.profile_links, profile_id);
            *stored_link_id = link_id;
        };
    }
    
    /// Join a platform - establishes initial connection between profile and platform
    /// Checks for blocks before allowing the join
    public entry fun join_platform(
        link: &mut ProfilePlatformLink,
        platform: &Platform,
        block_list_registry: &BlockListRegistry,
        ctx: &mut TxContext
    ) {
        // Verify sender is the link owner
        assert!(tx_context::sender(ctx) == link.owner, EUnauthorized);
        
        let platform_id = object::id(platform);
        let profile_id = link.profile_id;
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Check if the platform has blocked this profile
        let platform_id_addr = object::id_to_address(&platform_id);
        let profile_id_addr = object::id_to_address(&profile_id);
        let (has_platform_block_list, _platform_block_list_id) = block_list::find_block_list(block_list_registry, platform_id_addr);
        if (has_platform_block_list) {
            // We can't borrow the actual BlockList since it's owned by the platform,
            // so we use a platform helper function to check if profile is blocked
            assert!(!platform::is_profile_blocked(platform, profile_id_addr), EEntityBlocked);
        };
        
        // Check if user has already joined this platform
        if (!vector::contains(&link.platforms, &platform_id)) {
            // Add to platforms list
            vector::push_back(&mut link.platforms, platform_id);
            
            // Record join timestamp
            table::add(&mut link.join_timestamps, platform_id, current_time);
            
            // Initialize last active timestamp
            table::add(&mut link.last_active, platform_id, current_time);
            
            // Emit event using standardized events module
            event::emit(UserJoinedPlatformEvent {
                profile_id,
                platform_id,
                user: link.owner,
                timestamp: current_time,
            });
        };
    }
    
    /// Record an interaction between a user and a platform
    /// Checks for blocks before allowing the interaction
    public entry fun record_interaction(
        link: &mut ProfilePlatformLink,
        platform_id: ID,
        interaction_type: u8,
        block_list_registry: &BlockListRegistry,
        ctx: &mut TxContext
    ) {
        // Verify sender is the link owner
        assert!(tx_context::sender(ctx) == link.owner, EUnauthorized);
        
        // Ensure user has joined this platform
        assert!(vector::contains(&link.platforms, &platform_id), ELinkNotFound);
        
        let profile_id = link.profile_id;
        
        // Check if the platform has blocked this profile
        let platform_id_addr = object::id_to_address(&platform_id);
        let profile_id_addr = object::id_to_address(&profile_id);
        let (has_platform_block_list, _) = block_list::find_block_list(block_list_registry, platform_id_addr);
        if (has_platform_block_list) {
            // We need to check in the platform module if this profile is blocked
            assert!(!platform::is_profile_blocked_by_id(platform_id_addr, profile_id_addr), EEntityBlocked);
        };
        
        // Update last active timestamp
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        *table::borrow_mut(&mut link.last_active, platform_id) = current_time;
        
        // Emit interaction event that indexers can use
        event::emit(UserPlatformInteractionEvent {
            profile_id,
            platform_id,
            interaction_type,
            timestamp: current_time,
        });
    }
    
    // === Public Accessor Functions ===
    
    /// Check if a user has joined a platform
    public fun has_joined_platform(link: &ProfilePlatformLink, platform_id: ID): bool {
        vector::contains(&link.platforms, &platform_id)
    }
    
    /// Get all platforms a user has joined
    public fun get_joined_platforms(link: &ProfilePlatformLink): vector<ID> {
        link.platforms
    }
    
    /// Get when a user joined a platform
    public fun get_join_timestamp(link: &ProfilePlatformLink, platform_id: ID): (bool, u64) {
        if (table::contains(&link.join_timestamps, platform_id)) {
            (true, *table::borrow(&link.join_timestamps, platform_id))
        } else {
            (false, 0)
        }
    }
    
    /// Get when a user was last active on a platform
    public fun get_last_active(link: &ProfilePlatformLink, platform_id: ID): (bool, u64) {
        if (table::contains(&link.last_active, platform_id)) {
            (true, *table::borrow(&link.last_active, platform_id))
        } else {
            (false, 0)
        }
    }
    
    /// Find a profile-platform link by profile ID
    public fun find_profile_link(
        registry: &ProfilePlatformRegistry,
        profile_id: ID
    ): (bool, ID) {
        if (table::contains(&registry.profile_links, profile_id)) {
            (true, *table::borrow(&registry.profile_links, profile_id))
        } else {
            (false, object::id_from_address(@0x0))
        }
    }
    
    /// Emit a user reputation changed event (replacement for update_user_reputation)
    /// This function emits an event with reputation data but doesn't store it on-chain
    public fun emit_user_reputation_update(
        profile_id: ID,
        platform_id: ID,
        old_score: u64,
        new_score: u64,
        reason: vector<u8>,
        ctx: &mut TxContext
    ) {
        // Emit user reputation changed event that indexers can use
        event::emit(UserReputationChangedEvent {
            profile_id,
            platform_id,
            old_score,
            new_score,
            reason: std::string::utf8(reason),
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }
}