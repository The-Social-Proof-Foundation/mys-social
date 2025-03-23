// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Reputation module for the MySocial network
/// Manages user reputation points based on content creation, engagement, and tipping
module social_contracts::reputation {
    use mys::object::{Self, UID, ID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer;
    use mys::table::{Self, Table};

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EProfileNotFound: u64 = 1;

    /// Reputation storage for all profiles
    public struct ReputationRegistry has key {
        id: UID,
        /// Content creation points for each profile
        content_points: Table<address, u64>,
        /// Engagement points for each profile
        engagement_points: Table<address, u64>,
        /// Tipping points for each profile
        tip_points: Table<address, u64>,
    }

    /// Reputation points updated event
    public struct ReputationUpdatedEvent has copy, drop {
        profile_id: address,
        content_points: u64,
        engagement_points: u64,
        tip_points: u64,
        total_points: u64,
    }

    /// Create and share the global reputation registry
    /// This should be called once during system initialization
    public fun initialize(ctx: &mut TxContext) {
        let registry = ReputationRegistry {
            id: object::new(ctx),
            content_points: table::new(ctx),
            engagement_points: table::new(ctx),
            tip_points: table::new(ctx),
        };

        transfer::share_object(registry);
    }

    /// Add content creation points to a profile
    public fun add_content_points(
        profile_id: ID,
        points: u64,
        ctx: &mut TxContext
    ) {
        let profile_addr = object::id_to_address(&profile_id);
        add_content_points_internal(profile_addr, points, ctx)
    }

    /// Add engagement points to a profile
    public fun add_engagement_points(
        profile_id: ID,
        points: u64,
        ctx: &mut TxContext
    ) {
        let profile_addr = object::id_to_address(&profile_id);
        add_engagement_points_internal(profile_addr, points, ctx)
    }

    /// Add tipping points to a profile
    public fun add_tip_points(
        profile_id: ID,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let profile_addr = object::id_to_address(&profile_id);
        // Calculate points as 10% of MYS amount
        let points = amount / 10;
        if (points > 0) {
            add_tip_points_internal(profile_addr, points, ctx);
        }
    }

    /// Internal function to add content points
    public(package) fun add_content_points_internal(
        profile_addr: address,
        points: u64,
        _ctx: &mut TxContext
    ) {
        // Note: The reputation registry object would be passed in real implementation
        // For now this is a mock implementation
        // Would update points in the registry
        
        // Example event emission
        event::emit(ReputationUpdatedEvent {
            profile_id: profile_addr,
            content_points: points,
            engagement_points: 0,
            tip_points: 0,
            total_points: points,
        });
    }

    /// Internal function to add engagement points
    public(package) fun add_engagement_points_internal(
        profile_addr: address,
        points: u64,
        _ctx: &mut TxContext
    ) {
        // Mock implementation
        event::emit(ReputationUpdatedEvent {
            profile_id: profile_addr,
            content_points: 0,
            engagement_points: points,
            tip_points: 0,
            total_points: points,
        });
    }

    /// Internal function to add tip points
    public(package) fun add_tip_points_internal(
        profile_addr: address,
        points: u64,
        _ctx: &mut TxContext
    ) {
        // Mock implementation
        event::emit(ReputationUpdatedEvent {
            profile_id: profile_addr,
            content_points: 0,
            engagement_points: 0,
            tip_points: points,
            total_points: points,
        });
    }

    /// Get content points for a profile
    public fun get_content_points(registry: &ReputationRegistry, profile_id: address): u64 {
        if (!table::contains(&registry.content_points, profile_id)) {
            return 0
        };
        *table::borrow(&registry.content_points, profile_id)
    }

    /// Get engagement points for a profile
    public fun get_engagement_points(registry: &ReputationRegistry, profile_id: address): u64 {
        if (!table::contains(&registry.engagement_points, profile_id)) {
            return 0
        };
        *table::borrow(&registry.engagement_points, profile_id)
    }

    /// Get tip points for a profile
    public fun get_tip_points(registry: &ReputationRegistry, profile_id: address): u64 {
        if (!table::contains(&registry.tip_points, profile_id)) {
            return 0
        };
        *table::borrow(&registry.tip_points, profile_id)
    }

    /// Get total reputation points for a profile
    public fun get_total_points(registry: &ReputationRegistry, profile_id: address): u64 {
        let content = get_content_points(registry, profile_id);
        let engagement = get_engagement_points(registry, profile_id);
        let tip = get_tip_points(registry, profile_id);
        content + engagement + tip
    }
}