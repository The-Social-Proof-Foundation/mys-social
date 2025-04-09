// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Block list module for the MySocial network
/// Manages user blocking between wallet addresses
module social_contracts::block_list {
    use std::option::{Self, Option};
    use mys::object::{Self, UID, ID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer;
    use mys::table::{Self, Table};
    use mys::vec_set::{Self, VecSet};
    use mys::dynamic_field::{Self};
    
    /// Error codes
    const EUnauthorized: u64 = 0;
    const EAlreadyBlocked: u64 = 1;
    const ENotBlocked: u64 = 2;
    const ECannotBlockSelf: u64 = 3;
    const ERegistryNotFound: u64 = 4;

    /// Key for storing blocked wallets in the registry
    const BLOCKED_WALLETS_KEY: vector<u8> = b"blocked_wallets";

    /// Block list for a user's wallet
    public struct BlockList has key {
        id: UID,
        /// The wallet address this block list belongs to
        owner: address,
    }
    
    /// Registry to track all block lists
    public struct BlockListRegistry has key {
        id: UID,
        /// Table mapping wallet addresses to block list IDs
        wallet_block_lists: Table<address, address>,
    }

    /// Block event
    public struct UserBlockEvent has copy, drop {
        /// The blocker wallet address (who initiated the block)
        blocker: address,
        /// The blocked wallet address (who was blocked)
        blocked: address,
    }

    /// Unblock event
    public struct UserUnblockEvent has copy, drop {
        /// The blocker wallet address (who initiated the unblock)
        blocker: address,
        /// The unblocked wallet address (who was unblocked)
        unblocked: address,
    }

    /// Event emitted when a block list is created
    public struct BlockListCreatedEvent has copy, drop {
        owner: address,
        block_list_id: address,
    }

    /// Create a new block list
    public fun create_block_list(owner: address, ctx: &mut TxContext): BlockList {
        BlockList {
            id: object::new(ctx),
            owner,
        }
    }

    /// Create a new block list for the sender
    /// This is an explicit operation to create a block list, even if not blocking anyone yet
    public entry fun create_block_list_for_sender(registry: &mut BlockListRegistry, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        
        // Check if a block list already exists for the sender
        if (table::contains(&registry.wallet_block_lists, sender)) {
            return
        };
        
        // Create a new block list
        let block_list = create_block_list(sender, ctx);
        let block_list_id = object::uid_to_address(&block_list.id);
        
        // Register the block list
        table::add(&mut registry.wallet_block_lists, sender, block_list_id);
        
        // Initialize an empty blocked wallets set in the registry
        dynamic_field::add(&mut registry.id, get_blocked_wallets_key(sender), vec_set::empty<address>());
        
        // Emit block list created event
        event::emit(BlockListCreatedEvent {
            owner: sender,
            block_list_id,
        });
        
        // Return the block list to the caller
        transfer::transfer(block_list, sender);
    }

    /// Module initializer to create the block list registry
    fun init(ctx: &mut TxContext) {
        let registry = BlockListRegistry {
            id: object::new(ctx),
            wallet_block_lists: table::new(ctx),
        };
        
        // Share the registry to make it globally accessible
        transfer::share_object(registry);
    }
    
    /// Generate a unique key for storing a user's blocked wallets
    fun get_blocked_wallets_key(user_address: address): vector<u8> {
        let mut key = BLOCKED_WALLETS_KEY;
        let address_bytes = mys::bcs::to_bytes(&user_address);
        std::vector::append(&mut key, address_bytes);
        key
    }
    
    /// Block a wallet address
    /// Uses the caller's wallet address as the blocker
    public entry fun block_wallet(
        registry: &mut BlockListRegistry,
        blocked_wallet_address: address,
        ctx: &mut TxContext
    ) {
        // Get the sender address (wallet address of the blocker)
        let sender = tx_context::sender(ctx);
        
        // Cannot block self
        assert!(sender != blocked_wallet_address, ECannotBlockSelf);
        
        // Check if sender already has a block list
        let has_block_list = table::contains(&registry.wallet_block_lists, sender);
        
        if (has_block_list) {
            // Get key for finding blocked wallets
            let key = get_blocked_wallets_key(sender);
            
            // Get the blocked wallets set from registry
            let blocked_wallets = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut registry.id, key);
            
            // Check if already blocked
            if (vec_set::contains(blocked_wallets, &blocked_wallet_address)) {
                abort EAlreadyBlocked
            };
            
            // Add to blocked wallets
            vec_set::insert(blocked_wallets, blocked_wallet_address);
            
            // Emit block event
            event::emit(UserBlockEvent {
                blocker: sender,
                blocked: blocked_wallet_address,
            });
        } else {
            // Create a new block list for first-time blockers
            let block_list = create_block_list(sender, ctx);
            let block_list_id = object::uid_to_address(&block_list.id);
            
            // Register the block list
            table::add(&mut registry.wallet_block_lists, sender, block_list_id);
            
            // Create a new blocked wallets set with the blocked address
            let mut blocked_wallets = vec_set::empty<address>();
            vec_set::insert(&mut blocked_wallets, blocked_wallet_address);
            
            // Add the blocked wallets set to the registry
            dynamic_field::add(&mut registry.id, get_blocked_wallets_key(sender), blocked_wallets);
            
            // Emit block list created event
            event::emit(BlockListCreatedEvent {
                owner: sender,
                block_list_id,
            });
            
            // Emit block event
            event::emit(UserBlockEvent {
                blocker: sender,
                blocked: blocked_wallet_address,
            });
            
            // Return the block list to the caller
            transfer::transfer(block_list, sender);
        }
    }

    /// Unblock a wallet address
    /// Uses the caller's wallet address as the blocker
    public entry fun unblock_wallet(
        registry: &mut BlockListRegistry,
        blocked_wallet_address: address,
        ctx: &mut TxContext
    ) {
        // Get the sender address (wallet address of the blocker)
        let sender = tx_context::sender(ctx);
        
        // Check if there's a block list for this wallet
        if (!table::contains(&registry.wallet_block_lists, sender)) {
            abort ENotBlocked
        };
        
        // Get key for finding blocked wallets
        let key = get_blocked_wallets_key(sender);
        
        // Check if blocked wallets set exists
        if (!dynamic_field::exists_(&registry.id, key)) {
            abort ENotBlocked
        };
        
        // Get the blocked wallets set
        let blocked_wallets = dynamic_field::borrow_mut<vector<u8>, VecSet<address>>(&mut registry.id, key);
        
        // Check if the wallet is actually blocked
        if (!vec_set::contains(blocked_wallets, &blocked_wallet_address)) {
            abort ENotBlocked
        };
        
        // Remove from blocked wallets
        vec_set::remove(blocked_wallets, &blocked_wallet_address);
        
        // Emit unblock event
        event::emit(UserUnblockEvent {
            blocker: sender,
            unblocked: blocked_wallet_address,
        });
    }

    // === PUBLIC API ===

    /// Check if a wallet has a block list
    public fun has_block_list(registry: &BlockListRegistry, wallet_address: address): bool {
        table::contains(&registry.wallet_block_lists, wallet_address)
    }
    
    /// Find a block list ID for a wallet address
    public fun find_block_list_id(registry: &BlockListRegistry, wallet_address: address): Option<address> {
        if (table::contains(&registry.wallet_block_lists, wallet_address)) {
            option::some(*table::borrow(&registry.wallet_block_lists, wallet_address))
        } else {
            option::none()
        }
    }

    /// Check if a wallet address is blocked by a blocker
    public fun is_blocked(registry: &BlockListRegistry, blocker: address, blocked: address): bool {
        // First check if blocker has a block list
        if (!table::contains(&registry.wallet_block_lists, blocker)) {
            return false
        };
        
        // Get key for finding blocked wallets
        let key = get_blocked_wallets_key(blocker);
        
        // Check if blocked wallets set exists
        if (!dynamic_field::exists_(&registry.id, key)) {
            return false
        };
        
        // Get the blocked wallets set and check if blocked address is in it
        let blocked_wallets = dynamic_field::borrow<vector<u8>, VecSet<address>>(&registry.id, key);
        vec_set::contains(blocked_wallets, &blocked)
    }

    /// Get the number of blocked wallet addresses
    public fun blocked_count(registry: &BlockListRegistry, blocker: address): u64 {
        // First check if blocker has a block list
        if (!table::contains(&registry.wallet_block_lists, blocker)) {
            return 0
        };
        
        // Get key for finding blocked wallets
        let key = get_blocked_wallets_key(blocker);
        
        // Check if blocked wallets set exists
        if (!dynamic_field::exists_(&registry.id, key)) {
            return 0
        };
        
        // Get the blocked wallets set and return its size
        let blocked_wallets = dynamic_field::borrow<vector<u8>, VecSet<address>>(&registry.id, key);
        vec_set::size(blocked_wallets)
    }

    /// Get the list of blocked wallet addresses for a blocker
    public fun get_blocked_wallets(registry: &BlockListRegistry, blocker: address): vector<address> {
        // First check if blocker has a block list
        if (!table::contains(&registry.wallet_block_lists, blocker)) {
            return std::vector::empty()
        };
        
        // Get key for finding blocked wallets
        let key = get_blocked_wallets_key(blocker);
        
        // Check if blocked wallets set exists
        if (!dynamic_field::exists_(&registry.id, key)) {
            return std::vector::empty()
        };
        
        // Get the blocked wallets set and return its contents
        let blocked_wallets = dynamic_field::borrow<vector<u8>, VecSet<address>>(&registry.id, key);
        vec_set::into_keys(*blocked_wallets)
    }
}