// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Name service module for the MySocial platform.
/// This module implements a username registration and management system.
#[allow(unused_variable, duplicate_alias, unused_const, deprecated_usage, implicit_const_copy)]
module social_contracts::name_service {
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    
    use mys::object::{Self, UID, ID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer::{Self, public_transfer};
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::balance::{Self, Balance};
    use mys::mys::MYS;
    use mys::clock::{Self, Clock};
    
    /// Error codes
    const EUnauthorized: u64 = 0;
    const ENameRegistered: u64 = 1;
    const ENameNotRegistered: u64 = 2;
    const EInvalidName: u64 = 3;
    const EReservedName: u64 = 4;
    const EProfileHasName: u64 = 5;
    const EInsufficientPayment: u64 = 6;
    const ENameExpired: u64 = 7;
    const ENameNotExpired: u64 = 8;
    const ENameNotTransferable: u64 = 9;
    const EPriceNotSet: u64 = 10;
    const EInvalidDuration: u64 = 11;
    const ENotAdmin: u64 = 12;
    const EUserAlreadyHasUsername: u64 = 13;
    const EProfileRequired: u64 = 14;
    
    /// Name length categories for pricing
    const NAME_LENGTH_ULTRA_SHORT: u8 = 0;    // 2-4 characters
    const NAME_LENGTH_SHORT: u8 = 1;          // 5-7 characters
    const NAME_LENGTH_MEDIUM: u8 = 2;         // 8-12 characters
    const NAME_LENGTH_LONG: u8 = 3;           // 13+ characters
    
    /// Reserved usernames that cannot be registered
    const RESERVED_NAMES: vector<vector<u8>> = vector[
        b"admin", 
        b"administrator", 
        b"owner", 
        b"mod", 
        b"moderator", 
        b"staff", 
        b"support", 
        b"myso", 
        b"mysocial", 
        b"system", 
        b"root", 
        b"official",
        // Inappropriate names
        b"fuck",
        b"shit",
        b"ass",
        b"piss",
        b"cunt",
        b"asshole",
        b"dick",
        b"pussy",
        b"sex"
    ];
    
    /// Duration in seconds
    const SECONDS_PER_DAY: u64 = 86400;
    const SECONDS_PER_YEAR: u64 = 31536000;   // 365 days
    
    /// Name registry that stores all registered usernames
    public struct NameRegistry has key {
        id: UID,
        // Maps from name string to Username ID
        names: Table<String, address>,
        // Maps from profile ID to Username ID
        profile_names: Table<address, address>,
        // Maps from wallet address to Username ID (one username per wallet)
        owner_names: Table<address, address>,
        // Admin addresses with special privileges
        admins: Table<address, bool>,
        // Creator of the registry (super admin)
        creator: address,
        // Treasury to collect registration fees
        treasury: Balance<MYS>,
    }
    
    /// Username object representing a registered name
    public struct Username has key, store {
        id: UID,
        /// The actual username string
        name: String,
        /// The profile this username is assigned to (if any)
        profile_id: Option<address>,
        /// Original registration timestamp
        registered_at: u64,
        /// Expiration timestamp
        expires_at: u64,
        /// Last renewal timestamp
        last_renewal: u64,
        /// Status of the name
        status: u8,
        /// Flag if name is transferable
        transferable: bool,
        /// ID of the owner's profile
        owner: address,
    }
    
    /// Accessor functions
    public fun id(username: &Username): &UID {
        &username.id
    }
    
    public fun name(username: &Username): String {
        username.name
    }
    
    public fun owner(username: &Username): address {
        username.owner
    }
    
    public fun get_profile_id(username: &Username): Option<address> {
        username.profile_id
    }
    
    /// Get the username ID for a profile (if any)
    public fun get_username_for_profile(registry: &NameRegistry, profile_id: address): Option<address> {
        if (table::contains(&registry.profile_names, profile_id)) {
            option::some(*table::borrow(&registry.profile_names, profile_id))
        } else {
            option::none()
        }
    }
    
    /// Registry creation - call this once
    public fun create_registry(ctx: &mut TxContext): NameRegistry {
        let sender = tx_context::sender(ctx);
        let mut admins = table::new(ctx);
        // Add creator as admin
        table::add(&mut admins, sender, true);
        
        NameRegistry {
            id: object::new(ctx),
            names: table::new(ctx),
            profile_names: table::new(ctx),
            owner_names: table::new(ctx),
            admins,
            creator: sender,
            treasury: balance::zero(),
        }
    }
    
    /// Create and share registry as a shared object with a global ID
    /// Only call this once for the entire blockchain
    public entry fun create_and_share_registry(ctx: &mut TxContext) {
        let registry = create_registry(ctx);
        // Share the registry with a well-known ID for easy retrieval
        transfer::share_object(registry);
    }
    
    /// Create the global registry - this should be called once for initial setup
    public entry fun init_global_registry(ctx: &mut TxContext) {
        create_and_share_registry(ctx);
    }
    
    /// Calculate price based on name length and duration
    /// Takes into account the duration with volume discounts for longer registrations
    public fun calculate_price(name_length: u64, duration_epochs: u64): u64 {
        let length_category = if (name_length <= 4) {
            NAME_LENGTH_ULTRA_SHORT
        } else if (name_length <= 7) {
            NAME_LENGTH_SHORT
        } else if (name_length <= 12) {
            NAME_LENGTH_MEDIUM
        } else {
            NAME_LENGTH_LONG
        };
        
        // Base price in MYS (adjust as needed)
        let base_price = if (length_category == NAME_LENGTH_ULTRA_SHORT) {
            1_000_000_000_000 // 1,000 MYSO for ultra short names
        } else if (length_category == NAME_LENGTH_SHORT) {
            10_000_000_000 // 10 MYSO for short names
        } else if (length_category == NAME_LENGTH_MEDIUM) {
            5_000_000_000 // 5 MYSO for medium names
        } else {
            500_000_000 // 0.5 MYSO for long names
        };
        
        // Apply duration discount
        // For multi-year registrations, provide a discount
        let discount_multiplier = if (duration_epochs >= 12) {
            // 20% discount for 1+ year
            80
        } else if (duration_epochs >= 6) {
            // 10% discount for 6+ months
            90
        } else if (duration_epochs >= 3) {
            // 5% discount for 3+ months
            95
        } else {
            // No discount for short durations
            100
        };
        
        // Calculate price based on duration with discount
        (base_price * duration_epochs * discount_multiplier) / 100
    }
    
    /// Check if a name is reserved and cannot be registered
    public fun is_reserved_name(name: &String): bool {
        // For simplicity, since we don't have to_lowercase, we'll compare case-sensitively
        let name_bytes = string::as_bytes(name);
        
        let mut i = 0;
        let reserved_count = vector::length(&RESERVED_NAMES);
        
        while (i < reserved_count) {
            let reserved = *vector::borrow(&RESERVED_NAMES, i);
            
            // Simple case-insensitive comparison - convert to lowercase
            if (compare_bytes(name_bytes, &reserved)) {
                return true
            };
            i = i + 1;
        };
        
        false
    }
    
    /// Simple byte comparison (replace std::vector::equal)
    fun compare_bytes(a: &vector<u8>, b: &vector<u8>): bool {
        if (vector::length(a) != vector::length(b)) {
            return false
        };
        
        let mut i = 0;
        let len = vector::length(a);
        
        while (i < len) {
            // Simple lowercase comparison
            let byte_a = *vector::borrow(a, i);
            let byte_b = *vector::borrow(b, i);
            
            if (byte_a != byte_b) {
                // Try lowercase comparison for ASCII letters
                if (to_lowercase_byte(byte_a) != to_lowercase_byte(byte_b)) {
                    return false
                }
            };
            
            i = i + 1;
        };
        
        true
    }
    
    /// Convert a single ASCII byte to lowercase
    fun to_lowercase_byte(b: u8): u8 {
        if (b >= 65 && b <= 90) { // A-Z
            return b + 32 // convert to a-z
        };
        b
    }
    
    
    
    /// Register a username and assign it to a profile
    /// This unified function handles the entire process:
    /// 1. Validates the name
    /// 2. Processes payment
    /// 3. Creates the username object
    /// 4. Links it to the profile
    /// 5. Enforces the one-username-per-user policy
    public entry fun register_username(
        registry: &mut NameRegistry,
        profile_id: address,
        name: String,
        payment: &mut Coin<MYS>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Profile is required
        assert!(profile_id != @0x0, EProfileRequired);
        
        // Validate the name
        let name_bytes = string::as_bytes(&name);
        let name_length = vector::length(name_bytes);
        
        // Name length validation - between 2 and 50 characters
        assert!(name_length >= 2 && name_length <= 50, EInvalidName);
        
        // Check if name is reserved
        assert!(!is_reserved_name(&name), EReservedName);
        
        // Check that the name isn't already registered
        assert!(!table::contains(&registry.names, name), ENameRegistered);
        
        // Get sender
        let sender = tx_context::sender(ctx);
        
        // Check that the sender doesn't already have a username
        assert!(!table::contains(&registry.owner_names, sender), EUserAlreadyHasUsername);
        
        // Now we need to check that the profile doesn't already have a username
        assert!(!table::contains(&registry.profile_names, profile_id), EProfileHasName);
        
        // Use a default 1-year duration (12 epochs)
        let duration_epochs = 12;
        
        // Calculate price (with automatic discount for 1-year)
        let price = calculate_price(name_length, duration_epochs);
        
        // Ensure sufficient payment
        assert!(coin::value(payment) >= price, EInsufficientPayment);
        
        // Deduct payment
        let mut payment_balance = coin::balance_mut(payment);
        let paid_balance = balance::split(payment_balance, price);
        // Add payment to the registry treasury
        balance::join(&mut registry.treasury, paid_balance);
        
        // Get current time
        let now = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        
        // Calculate expiration (now + duration in seconds)
        let expires_at = now + (duration_epochs * SECONDS_PER_DAY * 30); // Approximate an epoch as 30 days
        
        // Create username object
        let username = Username {
            id: object::new(ctx),
            name: name, // Store as-is
            profile_id: option::some(profile_id),
            registered_at: now,
            expires_at,
            last_renewal: now,
            status: 1, // Active
            transferable: true,
            owner: sender,
        };
        
        // Get the username ID
        let username_id = object::uid_to_address(&username.id);
        
        // Add to registries
        table::add(&mut registry.names, name, username_id);
        table::add(&mut registry.profile_names, profile_id, username_id);
        table::add(&mut registry.owner_names, sender, username_id);
        
        // Transfer to the buyer
        public_transfer(username, sender);
        
        // Emit username registration event
        event::emit(UsernameRegisteredEvent {
            username_id,
            name,
            owner: sender,
            expires_at,
            registered_at: now
        });
        
        // Emit username assignment event
        event::emit(UsernameAssignedEvent {
            username_id,
            profile_id,
            name,
            assigned_at: now
        });
    }
    
    /// Remove username assignment from a profile, sender must be the owner
    public entry fun unassign_from_profile(
        registry: &mut NameRegistry,
        profile_id: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Verify profile has a username
        assert!(table::contains(&registry.profile_names, profile_id), ENameNotRegistered);
        
        // Get the username ID
        let username_id = *table::borrow(&registry.profile_names, profile_id);
        
        // Verify sender is associated with this username
        // This ensures only the owner can unassign their username
        assert!(table::contains(&registry.owner_names, sender), EUnauthorized);
        let sender_username_id = *table::borrow(&registry.owner_names, sender);
        assert!(sender_username_id == username_id, EUnauthorized);
        
        // Remove from profile registry
        table::remove(&mut registry.profile_names, profile_id);
        
        // Remove from owner registry
        table::remove(&mut registry.owner_names, sender);
        
        // Emit event
        event::emit(UsernameUnassignedEvent {
            username_id,
            profile_id,
            unassigned_at: tx_context::epoch_timestamp_ms(ctx) / 1000
        });
    }
    
    // === Admin Functions ===
    
    /// Check if an address is an admin of the registry
    public fun is_admin(registry: &NameRegistry, addr: address): bool {
        addr == registry.creator || table::contains(&registry.admins, addr)
    }
    
    /// Add an admin to the registry (only callable by existing admins)
    public entry fun add_admin(
        registry: &mut NameRegistry,
        new_admin: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // Verify caller is an admin
        assert!(is_admin(registry, sender), ENotAdmin);
        
        // Add new admin if not already one
        if (!table::contains(&registry.admins, new_admin)) {
            table::add(&mut registry.admins, new_admin, true);
        };
        
        // Emit event
        event::emit(AdminAddedEvent {
            registry_id: object::uid_to_address(&registry.id),
            admin: new_admin,
            added_by: sender,
            added_at: tx_context::epoch_timestamp_ms(ctx) / 1000
        });
    }
    
    /// Remove an admin from the registry (only callable by creator)
    public entry fun remove_admin(
        registry: &mut NameRegistry,
        admin_to_remove: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // Only creator can remove admins
        assert!(sender == registry.creator, ENotAdmin);
        
        // Remove admin if exists
        if (table::contains(&registry.admins, admin_to_remove)) {
            table::remove(&mut registry.admins, admin_to_remove);
        };
        
        // Emit event
        event::emit(AdminRemovedEvent {
            registry_id: object::uid_to_address(&registry.id),
            admin: admin_to_remove,
            removed_by: sender,
            removed_at: tx_context::epoch_timestamp_ms(ctx) / 1000
        });
    }
    
    /// Withdraw funds from the treasury (only callable by admins)
    public entry fun withdraw_from_treasury(
        registry: &mut NameRegistry,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // Verify caller is an admin
        assert!(is_admin(registry, sender), ENotAdmin);
        
        // Make sure treasury has enough funds
        assert!(balance::value(&registry.treasury) >= amount, EInsufficientPayment);
        
        // Extract the specified amount
        let withdraw_balance = balance::split(&mut registry.treasury, amount);
        
        // Create a coin from the balance and transfer to recipient
        let withdraw_coin = coin::from_balance(withdraw_balance, ctx);
        transfer::public_transfer(withdraw_coin, recipient);
        
        // Emit withdrawal event
        event::emit(TreasuryWithdrawalEvent {
            registry_id: object::uid_to_address(&registry.id),
            amount,
            recipient,
            withdrawn_by: sender,
            withdrawn_at: tx_context::epoch_timestamp_ms(ctx) / 1000
        });
    }
    
    /// Revoke a username (only callable by admins)
    /// This forcibly removes a username from the registry
    public entry fun revoke_username(
        registry: &mut NameRegistry,
        username: String,  // We'll use the name directly instead of ID
        reason: String,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // Verify caller is an admin
        assert!(is_admin(registry, sender), ENotAdmin);
        
        // Check if name exists in registry
        assert!(table::contains(&registry.names, username), ENameNotRegistered);
        
        // Get username ID
        let username_id = *table::borrow(&registry.names, username);
        
        // Since we can't iterate through the table, we'll need to receive
        // the profile_id as an additional parameter or use another approach
        // For now, we'll create a placeholder for the profile_id
        let mut profile_id_opt = option::none<address>();
        
        // Similarly, we can't iterate through all owners, but we can check the sender's address
        // This is a workaround for the lack of table enumeration
        if (table::contains(&registry.owner_names, sender)) {
            let owner_username_id = *table::borrow(&registry.owner_names, sender);
            if (owner_username_id == username_id) {
                table::remove(&mut registry.owner_names, sender);
            };
        };
        
        // Remove from registry
        table::remove(&mut registry.names, username);
        
        // Emit revocation event
        event::emit(UsernameRevokedEvent {
            username_id,
            name: username,
            profile_id: profile_id_opt,
            revoked_by: sender,
            reason,
            revoked_at: tx_context::epoch_timestamp_ms(ctx) / 1000
        });
    }
    
    /// Events
    public struct UsernameRegisteredEvent has copy, drop {
        username_id: address,
        name: String,
        owner: address,
        expires_at: u64,
        registered_at: u64
    }
    
    public struct UsernameAssignedEvent has copy, drop {
        username_id: address,
        profile_id: address,
        name: String,
        assigned_at: u64,
    }
    
    public struct UsernameUnassignedEvent has copy, drop {
        username_id: address,
        profile_id: address,
        unassigned_at: u64,
    }
    
    public struct UsernameRevokedEvent has copy, drop {
        username_id: address,
        name: String,
        profile_id: Option<address>,
        revoked_by: address,
        reason: String,
        revoked_at: u64,
    }
    
    public struct AdminAddedEvent has copy, drop {
        registry_id: address,
        admin: address,
        added_by: address,
        added_at: u64,
    }
    
    public struct AdminRemovedEvent has copy, drop {
        registry_id: address,
        admin: address,
        removed_by: address,
        removed_at: u64,
    }
    
    public struct TreasuryWithdrawalEvent has copy, drop {
        registry_id: address,
        amount: u64,
        recipient: address,
        withdrawn_by: address,
        withdrawn_at: u64,
    }
}