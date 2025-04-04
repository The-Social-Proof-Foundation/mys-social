// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Block list module for the MySocial network
/// Manages user blocking for profiles
module social_contracts::block_list {
    use mys::object::{Self, UID, ID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer;
    use mys::table::{Self, Table};
    use mys::vec_set::{Self, VecSet};
    
    use social_contracts::profile::{Self, Profile};

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EAlreadyBlocked: u64 = 1;
    const ENotBlocked: u64 = 2;
    const ECannotBlockSelf: u64 = 3;

    /// Block list for a profile
    public struct BlockList has key {
        id: UID,
        /// The profile this block list belongs to
        profile_id: address,
        /// Set of blocked profile IDs
        blocked_profiles: VecSet<address>,
    }
    
    /// Registry of all block lists
    public struct BlockListRegistry has key {
        id: UID,
        /// Table mapping profile IDs to block list IDs
        profile_block_lists: Table<address, address>,
    }

    /// Block event
    public struct BlockProfileEvent has copy, drop {
        blocker: address,
        blocked: address,
    }

    /// Unblock event
    public struct UnblockProfileEvent has copy, drop {
        blocker: address,
        unblocked: address,
    }

    /// Create a new block list
    public fun create_block_list(profile: &Profile, ctx: &mut TxContext): BlockList {
        let profile_id = object::uid_to_address(profile::id(profile));
        
        let block_list = BlockList {
            id: object::new(ctx),
            profile_id,
            blocked_profiles: vec_set::empty(),
        };
        
        block_list
    }

    /// Create a new block list and transfer to sender
    public entry fun create_and_register_block_list(profile: &Profile, ctx: &mut TxContext) {
        let block_list = create_block_list(profile, ctx);
        transfer::transfer(block_list, tx_context::sender(ctx));
    }

    /// Block a profile
    public entry fun block_profile(
        block_list: &mut BlockList,
        blocker_profile: &Profile,
        blocked_profile_id: address,
        ctx: &mut TxContext
    ) {
        // Verify caller owns the block list's profile
        assert!(profile::owner(blocker_profile) == tx_context::sender(ctx), EUnauthorized);
        
        // Verify block list belongs to caller's profile
        let blocker_id = object::uid_to_address(profile::id(blocker_profile));
        assert!(block_list.profile_id == blocker_id, EUnauthorized);
        
        // Cannot block self
        assert!(blocker_id != blocked_profile_id, ECannotBlockSelf);
        
        // Check if already blocked
        assert!(!vec_set::contains(&block_list.blocked_profiles, &blocked_profile_id), EAlreadyBlocked);
        
        // Add to blocked profiles
        vec_set::insert(&mut block_list.blocked_profiles, blocked_profile_id);
        
        // Emit block event
        event::emit(BlockProfileEvent {
            blocker: blocker_id,
            blocked: blocked_profile_id,
        });
    }

    /// Unblock a profile
    public entry fun unblock_profile(
        block_list: &mut BlockList,
        blocker_profile: &Profile,
        blocked_profile_id: address,
        ctx: &mut TxContext
    ) {
        // Verify caller owns the block list's profile
        assert!(profile::owner(blocker_profile) == tx_context::sender(ctx), EUnauthorized);
        
        // Verify block list belongs to caller's profile
        let blocker_id = object::uid_to_address(profile::id(blocker_profile));
        assert!(block_list.profile_id == blocker_id, EUnauthorized);
        
        // Check if blocked
        assert!(vec_set::contains(&block_list.blocked_profiles, &blocked_profile_id), ENotBlocked);
        
        // Remove from blocked profiles
        vec_set::remove(&mut block_list.blocked_profiles, &blocked_profile_id);
        
        // Emit unblock event
        event::emit(UnblockProfileEvent {
            blocker: blocker_id,
            unblocked: blocked_profile_id,
        });
    }

    // === Getters ===

    /// Check if a profile is blocked
    public fun is_blocked(block_list: &BlockList, profile_id: address): bool {
        vec_set::contains(&block_list.blocked_profiles, &profile_id)
    }

    /// Get the number of blocked profiles
    public fun blocked_count(block_list: &BlockList): u64 {
        vec_set::size(&block_list.blocked_profiles)
    }

    /// Get the list of blocked profiles
    public fun get_blocked_profiles(block_list: &BlockList): vector<address> {
        vec_set::into_keys(*&block_list.blocked_profiles)
    }

    /// Get the profile ID this block list belongs to
    public fun profile_id(block_list: &BlockList): address {
        block_list.profile_id
    }
    
    /// Find a block list in the registry by profile ID
    public fun find_block_list(registry: &BlockListRegistry, profile_id: address): (bool, address) {
        if (table::contains(&registry.profile_block_lists, profile_id)) {
            (true, *table::borrow(&registry.profile_block_lists, profile_id))
        } else {
            (false, @0x0)
        }
    }
}