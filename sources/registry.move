// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Common registry module for MySocial platform
/// Provides standardized registry patterns for various platform components
module social_contracts::registry {
    use std::string::{Self, String};
    use std::vector;
    use std::option;
    use mys::object::{Self, UID, ID};
    use mys::transfer;
    use mys::tx_context::{Self, TxContext};
    use mys::table::{Self, Table};
    
    // === Errors ===
    /// Entity already registered
    const EAlreadyRegistered: u64 = 0;
    /// Entity not found
    const ENotFound: u64 = 1;
    /// Invalid operation
    const EInvalidOperation: u64 = 2;
    
    // === Structs ===
    
    /// Master registry for the MySocial platform
    /// This allows discovery of all other registries
    public struct MasterRegistry has key {
        id: UID,
        // Map from registry type name to registry ID
        registries: Table<String, ID>,
        // All registry types
        registry_types: vector<String>,
    }
    
    // === Registry Types ===
    
    /// User registry entry
    public struct UserEntry has store, copy, drop {
        user_id: ID,
        address: address,
        profile_id: Option<ID>,
        token_id: Option<address>,
        reputation_score: u64,
        registration_time: u64,
    }
    
    /// Platform registry entry
    public struct PlatformEntry has store, copy, drop {
        platform_id: ID,
        name: String,
        owner: address,
        token_id: Option<address>,
        reputation_score: u64,
        verified: bool,
        registration_time: u64,
    }
    
    /// Token registry entry
    public struct TokenEntry has store, copy, drop {
        token_id: address,
        name: String,
        symbol: String,
        owner: address,
        is_platform_token: bool,
        supply_cap: u64,
        registration_time: u64,
    }
    
    // === Registry Creation ===
    
    /// Initialize the registry system
    fun init(ctx: &mut TxContext) {
        // Create and share master registry
        transfer::share_object(
            MasterRegistry {
                id: object::new(ctx),
                registries: table::new(ctx),
                registry_types: vector::empty(),
            }
        );
    }
    
    /// Register a registry in the master registry
    public fun register_registry(
        master: &mut MasterRegistry,
        registry_type: vector<u8>,
        registry_id: ID,
        ctx: &mut TxContext
    ) {
        let registry_type_str = string::utf8(registry_type);
        
        // Make sure registry type doesn't already exist
        assert!(!table::contains(&master.registries, registry_type_str), EAlreadyRegistered);
        
        // Add to master registry
        table::add(&mut master.registries, registry_type_str, registry_id);
        vector::push_back(&mut master.registry_types, registry_type_str);
    }
    
    /// Get registry ID by type
    public fun get_registry_id(
        master: &MasterRegistry,
        registry_type: vector<u8>
    ): ID {
        let registry_type_str = string::utf8(registry_type);
        
        assert!(table::contains(&master.registries, registry_type_str), ENotFound);
        *table::borrow(&master.registries, registry_type_str)
    }
    
    /// Check if a registry type exists
    public fun has_registry_type(
        master: &MasterRegistry,
        registry_type: vector<u8>
    ): bool {
        let registry_type_str = string::utf8(registry_type);
        table::contains(&master.registries, registry_type_str)
    }
    
    /// Get all registry types
    public fun get_all_registry_types(
        master: &MasterRegistry
    ): vector<String> {
        master.registry_types
    }
    
    // === Generic Registration Functions ===
    
    /// Generic function to register an entity by ID in a table
    public fun register_entity<T: store + copy + drop>(
        registry_table: &mut Table<ID, T>,
        entity_id: ID, 
        entity_data: T
    ) {
        if (!table::contains(registry_table, entity_id)) {
            table::add(registry_table, entity_id, entity_data);
        } else {
            // If already exists, update it
            let stored_entity = table::borrow_mut(registry_table, entity_id);
            *stored_entity = entity_data;
        };
    }
    
    /// Generic function to register an entity by name
    public fun register_entity_by_name<T: store + copy + drop>(
        registry_table: &mut Table<String, T>,
        name: vector<u8>,
        entity_data: T
    ) {
        let name_str = string::utf8(name);
        
        if (!table::contains(registry_table, name_str)) {
            table::add(registry_table, name_str, entity_data);
        } else {
            // If already exists, update it
            let stored_entity = table::borrow_mut(registry_table, name_str);
            *stored_entity = entity_data;
        };
    }
    
    /// Retrieve a user entry by ID
    public fun get_user_entry(
        registry_table: &Table<ID, UserEntry>,
        entity_id: ID
    ): (bool, UserEntry) {
        if (table::contains(registry_table, entity_id)) {
            (true, *table::borrow(registry_table, entity_id))
        } else {
            // Return default value if not found - caller must check the boolean
            (false, get_default_user_entry())
        }
    }
    
    /// Retrieve a platform entry by ID
    public fun get_platform_entry(
        registry_table: &Table<ID, PlatformEntry>,
        entity_id: ID
    ): (bool, PlatformEntry) {
        if (table::contains(registry_table, entity_id)) {
            (true, *table::borrow(registry_table, entity_id))
        } else {
            // Return default value if not found - caller must check the boolean
            (false, get_default_platform_entry())
        }
    }
    
    /// Retrieve a token entry by ID
    public fun get_token_entry(
        registry_table: &Table<address, TokenEntry>,
        token_id: address
    ): (bool, TokenEntry) {
        if (table::contains(registry_table, token_id)) {
            (true, *table::borrow(registry_table, token_id))
        } else {
            // Return default value if not found - caller must check the boolean
            (false, get_default_token_entry())
        }
    }
    
    /// Get platform entry by name
    public fun get_platform_by_name(
        registry_table: &Table<String, PlatformEntry>,
        name: vector<u8>
    ): (bool, PlatformEntry) {
        let name_str = string::utf8(name);
        
        if (table::contains(registry_table, name_str)) {
            (true, *table::borrow(registry_table, name_str))
        } else {
            // Return default value if not found - caller must check the boolean
            (false, get_default_platform_entry())
        }
    }
    
    /// Get token entry by name
    public fun get_token_by_name(
        registry_table: &Table<String, TokenEntry>,
        name: vector<u8>
    ): (bool, TokenEntry) {
        let name_str = string::utf8(name);
        
        if (table::contains(registry_table, name_str)) {
            (true, *table::borrow(registry_table, name_str))
        } else {
            // Return default value if not found - caller must check the boolean
            (false, get_default_token_entry())
        }
    }
    
    /// Get a default entity - specialized for each type
    public fun get_default_user_entry(): UserEntry {
        UserEntry {
            user_id: object::id_from_address(@0x0),
            address: @0x0,
            profile_id: option::none(),
            token_id: option::none(),
            reputation_score: 0,
            registration_time: 0,
        }
    }
    
    /// Get default platform entry
    public fun get_default_platform_entry(): PlatformEntry {
        PlatformEntry {
            platform_id: object::id_from_address(@0x0),
            name: string::utf8(b""),
            owner: @0x0,
            token_id: option::none(),
            reputation_score: 0,
            verified: false,
            registration_time: 0,
        }
    }
    
    /// Get default token entry
    public fun get_default_token_entry(): TokenEntry {
        TokenEntry {
            token_id: @0x0,
            name: string::utf8(b""),
            symbol: string::utf8(b""),
            owner: @0x0,
            is_platform_token: false,
            supply_cap: 0,
            registration_time: 0,
        }
    }
    
    // === Registry Creation Templates ===
    
    /// Create a standard ID-based registry table
    public fun create_id_registry<T: store + copy + drop>(ctx: &mut TxContext): Table<ID, T> {
        table::new<ID, T>(ctx)
    }
    
    /// Create a standard name-based registry table
    public fun create_name_registry<T: store + copy + drop>(ctx: &mut TxContext): Table<String, T> {
        table::new<String, T>(ctx)
    }
}