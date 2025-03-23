// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Social graph module for the MySocial network
/// Manages social relationships between users (following/followers)
module social_contracts::social_graph {
    use std::vector;
    
    use mys::object::{Self, UID, ID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer;
    use mys::table::{Self, Table};
    use mys::vec_set::{Self, VecSet};
    
    use social_contracts::profile::{Self, Profile};

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EAlreadyFollowing: u64 = 1;
    const ENotFollowing: u64 = 2;
    const ECannotFollowSelf: u64 = 3;

    /// Global social graph object that tracks relationships between users
    public struct SocialGraph has key {
        id: UID,
        /// Table mapping profile IDs to sets of profiles they are following
        following: Table<address, VecSet<address>>,
        /// Table mapping profile IDs to sets of profiles following them
        followers: Table<address, VecSet<address>>,
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

    /// Create and share the global social graph object
    /// This should be called once during system initialization
    public fun initialize(ctx: &mut TxContext) {
        let social_graph = SocialGraph {
            id: object::new(ctx),
            following: table::new(ctx),
            followers: table::new(ctx),
        };

        transfer::share_object(social_graph);
    }

    /// Follow a profile
    public entry fun follow(
        social_graph: &mut SocialGraph,
        follower_profile: &Profile,
        following_id: address,
        ctx: &mut TxContext
    ) {
        // Get follower ID
        let follower_id = object::uid_to_address(profile::id(follower_profile));
        
        // Cannot follow self
        assert!(follower_id != following_id, ECannotFollowSelf);
        
        // Verify authorization
        assert!(profile::owner(follower_profile) == tx_context::sender(ctx), EUnauthorized);
        
        // Initialize follower's following set if it doesn't exist
        if (!table::contains(&social_graph.following, follower_id)) {
            table::add(&mut social_graph.following, follower_id, vec_set::empty());
        };
        
        // Initialize followed's followers set if it doesn't exist
        if (!table::contains(&social_graph.followers, following_id)) {
            table::add(&mut social_graph.followers, following_id, vec_set::empty());
        };
        
        // Get mutable references to the sets
        let follower_following = table::borrow_mut(&mut social_graph.following, follower_id);
        let following_followers = table::borrow_mut(&mut social_graph.followers, following_id);
        
        // Check if already following
        assert!(!vec_set::contains(follower_following, &following_id), EAlreadyFollowing);
        
        // Add to sets
        vec_set::insert(follower_following, following_id);
        vec_set::insert(following_followers, follower_id);
        
        // Emit follow event
        event::emit(FollowEvent {
            follower: follower_id,
            following: following_id,
        });
    }

    /// Unfollow a profile
    public entry fun unfollow(
        social_graph: &mut SocialGraph,
        follower_profile: &Profile,
        following_id: address,
        ctx: &mut TxContext
    ) {
        // Get follower ID
        let follower_id = object::uid_to_address(profile::id(follower_profile));
        
        // Verify authorization
        assert!(profile::owner(follower_profile) == tx_context::sender(ctx), EUnauthorized);
        
        // Check if following sets exist
        assert!(table::contains(&social_graph.following, follower_id), ENotFollowing);
        assert!(table::contains(&social_graph.followers, following_id), ENotFollowing);
        
        // Get mutable references to the sets
        let follower_following = table::borrow_mut(&mut social_graph.following, follower_id);
        let following_followers = table::borrow_mut(&mut social_graph.followers, following_id);
        
        // Check if following
        assert!(vec_set::contains(follower_following, &following_id), ENotFollowing);
        
        // Remove from sets
        vec_set::remove(follower_following, &following_id);
        vec_set::remove(following_followers, &follower_id);
        
        // Emit unfollow event
        event::emit(UnfollowEvent {
            follower: follower_id,
            unfollowed: following_id,
        });
    }

    // === Getters ===

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