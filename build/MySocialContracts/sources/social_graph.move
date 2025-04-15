// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Social graph module for the MySocial network
/// Manages social relationships between users (following/followers)
#[allow(duplicate_alias, unused_use, unused_const)]
module social_contracts::social_graph {
    use std::vector;
    use std::option;
    use std::string::{Self, String};
    
    use mys::object::{Self, UID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer;
    use mys::table::{Self, Table};
    use mys::vec_set::{Self, VecSet};
    
    use social_contracts::profile;
    use social_contracts::upgrade;

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EAlreadyFollowing: u64 = 1;
    const ENotFollowing: u64 = 2;
    const ECannotFollowSelf: u64 = 3;
    const EProfileNotFound: u64 = 4;
    const EWrongVersion: u64 = 5;

    /// Global social graph object that tracks relationships between users
    public struct SocialGraph has key {
        id: UID,
        /// Table mapping profile IDs to sets of profiles they are following
        following: Table<address, VecSet<address>>,
        /// Table mapping profile IDs to sets of profiles following them
        followers: Table<address, VecSet<address>>,
        /// Current version of the object
        version: u64,
    }

    /// Follow event
    public struct FollowEvent has copy, drop {
        follower: address,
        following: address,
    }

    /// Unfollow event
    public struct UnfollowEvent has copy, drop {
        follower: address,
        unfollowed: address,
    }

    /// Module initializer to create the social graph
    fun init(ctx: &mut TxContext) {
        let social_graph = SocialGraph {
            id: object::new(ctx),
            following: table::new(ctx),
            followers: table::new(ctx),
            version: upgrade::current_version(),
        };

        // Share the social graph to make it globally accessible
        transfer::share_object(social_graph);
    }

    /// Follow a profile by address
    public entry fun follow(
        social_graph: &mut SocialGraph,
        registry: &profile::UsernameRegistry,
        following_profile_id: address,
        ctx: &mut TxContext
    ) {
        // Check version compatibility
        assert!(social_graph.version == upgrade::current_version(), EWrongVersion);
        
        let sender = tx_context::sender(ctx);
        
        // Look up the caller's profile ID from registry
        let mut caller_profile_id_opt = profile::lookup_profile_by_owner(registry, sender);
        assert!(option::is_some(&caller_profile_id_opt), EProfileNotFound);
        
        // Extract follower profile ID
        let follower_profile_id = option::extract(&mut caller_profile_id_opt);
        
        // Cannot follow self
        assert!(follower_profile_id != following_profile_id, ECannotFollowSelf);
        
        // Initialize follower's following set if it doesn't exist
        if (!table::contains(&social_graph.following, follower_profile_id)) {
            table::add(&mut social_graph.following, follower_profile_id, vec_set::empty());
        };
        
        // Initialize followed's followers set if it doesn't exist
        if (!table::contains(&social_graph.followers, following_profile_id)) {
            table::add(&mut social_graph.followers, following_profile_id, vec_set::empty());
        };
        
        // Get mutable references to the sets
        let follower_following = table::borrow_mut(&mut social_graph.following, follower_profile_id);
        let following_followers = table::borrow_mut(&mut social_graph.followers, following_profile_id);
        
        // Check if already following
        assert!(!vec_set::contains(follower_following, &following_profile_id), EAlreadyFollowing);
        
        // Add to sets
        vec_set::insert(follower_following, following_profile_id);
        vec_set::insert(following_followers, follower_profile_id);
        
        // Emit follow event
        event::emit(FollowEvent {
            follower: follower_profile_id,
            following: following_profile_id,
        });
    }

    /// Unfollow a profile by address
    public entry fun unfollow(
        social_graph: &mut SocialGraph,
        registry: &profile::UsernameRegistry,
        following_profile_id: address,
        ctx: &mut TxContext
    ) {
        // Check version compatibility
        assert!(social_graph.version == upgrade::current_version(), EWrongVersion);
        
        let sender = tx_context::sender(ctx);
        
        // Look up the caller's profile ID from registry
        let mut caller_profile_id_opt = profile::lookup_profile_by_owner(registry, sender);
        assert!(option::is_some(&caller_profile_id_opt), EProfileNotFound);
        
        // Extract follower profile ID
        let follower_profile_id = option::extract(&mut caller_profile_id_opt);
        
        // Check if following sets exist
        assert!(table::contains(&social_graph.following, follower_profile_id), ENotFollowing);
        assert!(table::contains(&social_graph.followers, following_profile_id), ENotFollowing);
        
        // Get mutable references to the sets
        let follower_following = table::borrow_mut(&mut social_graph.following, follower_profile_id);
        let following_followers = table::borrow_mut(&mut social_graph.followers, following_profile_id);
        
        // Check if following
        assert!(vec_set::contains(follower_following, &following_profile_id), ENotFollowing);
        
        // Remove from sets
        vec_set::remove(follower_following, &following_profile_id);
        vec_set::remove(following_followers, &follower_profile_id);
        
        // Emit unfollow event
        event::emit(UnfollowEvent {
            follower: follower_profile_id,
            unfollowed: following_profile_id,
        });
    }

    /// Migrate the social graph to a new version
    /// Only callable by the admin with the AdminCap
    public entry fun migrate_social_graph(
        social_graph: &mut SocialGraph,
        _: &upgrade::AdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        
        // Verify this is an upgrade (new version > current version)
        assert!(social_graph.version < current_version, EWrongVersion);
        
        // Remember old version and update to new version
        let old_version = social_graph.version;
        social_graph.version = current_version;
        
        // Emit event for object migration
        let graph_id = object::id(social_graph);
        upgrade::emit_migration_event(
            graph_id,
            string::utf8(b"SocialGraph"),
            old_version,
            tx_context::sender(ctx)
        );
        
        // Any migration logic can be added here for future upgrades
    }

    /// Get a mutable reference to the version field (for upgrade module)
    public fun borrow_version_mut(social_graph: &mut SocialGraph): &mut u64 {
        &mut social_graph.version
    }

    // === Getters ===

    /// Get the version of the social graph
    public fun version(social_graph: &SocialGraph): u64 {
        social_graph.version
    }

    /// Check if a profile is following another profile
    public fun is_following(social_graph: &SocialGraph, follower_id: address, following_id: address): bool {
        if (!table::contains(&social_graph.following, follower_id)) {
            return false
        };
        
        let follower_following = table::borrow(&social_graph.following, follower_id);
        vec_set::contains(follower_following, &following_id)
    }

    /// Get the number of profiles a user is following
    public fun following_count(social_graph: &SocialGraph, profile_id: address): u64 {
        if (!table::contains(&social_graph.following, profile_id)) {
            return 0
        };
        
        let following = table::borrow(&social_graph.following, profile_id);
        vec_set::size(following)
    }

    /// Get the number of followers a profile has
    public fun follower_count(social_graph: &SocialGraph, profile_id: address): u64 {
        if (!table::contains(&social_graph.followers, profile_id)) {
            return 0
        };
        
        let followers = table::borrow(&social_graph.followers, profile_id);
        vec_set::size(followers)
    }

    /// Get the list of profiles a user is following
    public fun get_following(social_graph: &SocialGraph, profile_id: address): vector<address> {
        if (!table::contains(&social_graph.following, profile_id)) {
            return vector::empty()
        };
        
        let following = table::borrow(&social_graph.following, profile_id);
        vec_set::into_keys(*following)
    }

    /// Get the list of followers for a profile
    public fun get_followers(social_graph: &SocialGraph, profile_id: address): vector<address> {
        if (!table::contains(&social_graph.followers, profile_id)) {
            return vector::empty()
        };
        
        let followers = table::borrow(&social_graph.followers, profile_id);
        vec_set::into_keys(*followers)
    }
}