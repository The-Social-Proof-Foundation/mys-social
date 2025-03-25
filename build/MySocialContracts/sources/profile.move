// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Profile module for the MySocial network
/// Handles user identity, profile creation, management, and username registration
#[allow(unused_const, duplicate_alias)]
module social_contracts::profile {
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    
    use mys::object::{Self, UID, ID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer::{Self, public_transfer};
    use mys::url::{Self, Url};
    use mys::dynamic_field;
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::balance::{Self, Balance};
    use mys::mys::MYS;
    use mys::clock::{Self, Clock};

    /// Error codes
    const EProfileAlreadyExists: u64 = 0;
    const EUnauthorized: u64 = 1;
    const EUsernameAlreadySet: u64 = 2;
    const EUsernameNotRegistered: u64 = 3;
    const EInvalidUsername: u64 = 4;
    const ENameRegistryMismatch: u64 = 5;
    const EProfileCreateFailed: u64 = 6;
    const EReservedName: u64 = 7;
    const EInsufficientPayment: u64 = 8;
    const EUsernameNotAvailable: u64 = 9;
    const ENotAdmin: u64 = 10;
    const EProfileMustHaveUsername: u64 = 11;

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

    /// Field names for dynamic fields
    const USERNAME_FIELD: vector<u8> = b"username";
    const USERNAME_EXPIRY_FIELD: vector<u8> = b"username_expiry";
    const USERNAME_REGISTERED_AT_FIELD: vector<u8> = b"username_registered_at";

    /// Username Registry that stores mappings between usernames and profiles
    public struct UsernameRegistry has key {
        id: UID,
        // Maps username string to profile ID
        usernames: Table<String, address>,
        // Maps addresses (owners) to their profile IDs
        address_profiles: Table<address, address>,
        // Admin addresses with special privileges
        admins: Table<address, bool>,
        // Creator of the registry (super admin)
        creator: address,
        // Treasury to collect registration fees
        treasury: Balance<MYS>,
    }

    /// Profile object that contains user information
    public struct Profile has key, store {
        id: UID,
        /// Display name of the profile (optional)
        display_name: Option<String>,
        /// Bio of the profile
        bio: String,
        /// Profile picture URL
        profile_picture: Option<Url>,
        /// Cover photo URL
        cover_photo: Option<Url>,
        /// Email address 
        email: Option<String>,
        /// Profile creation timestamp
        created_at: u64,
        /// Profile owner address
        owner: address,
    }

    // === Events ===

    /// Profile created event
    public struct ProfileCreatedEvent has copy, drop {
        profile_id: address,
        display_name: String,
        username: Option<String>,
        has_profile_picture: bool,
        has_cover_photo: bool,
        has_email: bool,
        owner: address,
    }

    /// Profile updated event
    public struct ProfileUpdatedEvent has copy, drop {
        profile_id: address,
        display_name: Option<String>,
        username: Option<String>,
        has_profile_picture: bool,
        has_cover_photo: bool,
        has_email: bool,
        owner: address,
    }

    /// Username updated event
    public struct UsernameUpdatedEvent has copy, drop {
        profile_id: address,
        old_username: String,
        new_username: String,
        owner: address,
    }
    
    /// Username registered event
    public struct UsernameRegisteredEvent has copy, drop {
        profile_id: address,
        username: String,
        owner: address,
        expires_at: u64,
        registered_at: u64
    }

    /// Username transferred event
    public struct UsernameTransferredEvent has copy, drop {
        profile_id: address,
        username: String,
        old_owner: address,
        new_owner: address,
        transferred_at: u64
    }

    /// Module initializer to create the username registry
    fun init(ctx: &mut TxContext) {
        let registry = create_username_registry(ctx);
        // Share the registry to make it globally accessible
        transfer::share_object(registry);
    }

    // === Core Registry Functions ===

    /// Create a new username registry (normally done by init)
    fun create_username_registry(ctx: &mut TxContext): UsernameRegistry {
        let sender = tx_context::sender(ctx);
        let mut admins = table::new(ctx);
        // Add creator as admin
        table::add(&mut admins, sender, true);
        
        UsernameRegistry {
            id: object::new(ctx),
            usernames: table::new(ctx),
            address_profiles: table::new(ctx),
            admins,
            creator: sender,
            treasury: balance::zero(),
        }
    }

    /// Check if an address is an admin of the registry
    public fun is_admin(registry: &UsernameRegistry, addr: address): bool {
        addr == registry.creator || table::contains(&registry.admins, addr)
    }

    /// Add an admin to the registry (only callable by existing admins)
    public entry fun add_admin(
        registry: &mut UsernameRegistry,
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
    }

    /// Remove an admin from the registry (only callable by creator)
    public entry fun remove_admin(
        registry: &mut UsernameRegistry,
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
    }

    /// Withdraw funds from the treasury (only callable by admins)
    public entry fun withdraw_from_treasury(
        registry: &mut UsernameRegistry,
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
    }

    // === Username Management Functions ===

    /// Check if a name is reserved and cannot be registered
    public fun is_reserved_name(name: &String): bool {
        // Convert name string to lowercase for comparison
        let name_bytes = string::as_bytes(name);
        let lowercase_name = to_lowercase_bytes(name_bytes);
        
        let mut i = 0;
        let reserved_count = vector::length(&RESERVED_NAMES);
        
        while (i < reserved_count) {
            let reserved = *vector::borrow(&RESERVED_NAMES, i);
            
            // Exact match with reserved name (case-insensitive)
            if (vector::length(&lowercase_name) == vector::length(&reserved)) {
                let mut is_match = true;
                let mut j = 0;
                while (j < vector::length(&reserved)) {
                    if (*vector::borrow(&lowercase_name, j) != *vector::borrow(&reserved, j)) {
                        is_match = false;
                        break
                    };
                    j = j + 1;
                };
                
                if (is_match) {
                    return true
                };
            };
            
            i = i + 1;
        };
        
        false
    }

    /// Calculate price based on name length and duration
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
        
        // Base price in MYS (significantly reduced to be more affordable)
        let base_price = if (length_category == NAME_LENGTH_ULTRA_SHORT) {
            5_000_000_000 // 5 MYSO for ultra short names (reduced from 100)
        } else if (length_category == NAME_LENGTH_SHORT) {
            1_000_000_000 // 1 MYSO for short names (reduced from 10)
        } else if (length_category == NAME_LENGTH_MEDIUM) {
            500_000_000 // 0.5 MYSO for medium names (reduced from 5)
        } else {
            100_000_000 // 0.1 MYSO for long names (reduced from 0.5)
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

    /// Convert a byte vector to lowercase
    fun to_lowercase_bytes(bytes: &vector<u8>): vector<u8> {
        let mut result = vector::empty<u8>();
        let mut i = 0;
        let len = vector::length(bytes);
        
        while (i < len) {
            let b = *vector::borrow(bytes, i);
            vector::push_back(&mut result, to_lowercase_byte(b));
            i = i + 1;
        };
        
        result
    }

    /// Convert a single ASCII byte to lowercase
    fun to_lowercase_byte(b: u8): u8 {
        if (b >= 65 && b <= 90) { // A-Z
            return b + 32 // convert to a-z
        };
        b
    }

    // === Profile Creation and Management ===

    /// Create a new profile with a required username
    /// This is the main entry point for new users, combining profile and username creation
    public entry fun create_profile_with_username(
        registry: &mut UsernameRegistry,
        display_name: String,
        username: String,
        bio: String,
        profile_picture_url: vector<u8>,
        cover_photo_url: vector<u8>,
        email: String,
        payment: &mut Coin<MYS>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let now = tx_context::epoch(ctx);
        
        // Validate the username
        let username_bytes = string::as_bytes(&username);
        let username_length = vector::length(username_bytes);
        
        // Name length validation - between 2 and 50 characters
        assert!(username_length >= 2 && username_length <= 50, EInvalidUsername);
        
        // Check if name is reserved
        assert!(!is_reserved_name(&username), EReservedName);
        
        // Check that the username isn't already registered
        assert!(!table::contains(&registry.usernames, username), EUsernameNotAvailable);
        
        // Check that the sender doesn't already have a profile
        assert!(!table::contains(&registry.address_profiles, owner), EProfileAlreadyExists);
        
        // Use a default 1-year duration (12 epochs)
        let duration_epochs = 12;
        
        // Calculate price for the username
        let price = calculate_price(username_length, duration_epochs);
        
        // Ensure sufficient payment
        let payment_value = coin::value(payment);
        assert!(payment_value >= price, EInsufficientPayment);
        
        // Deduct payment
        let payment_balance = coin::balance_mut(payment);
        let paid_balance = balance::split(payment_balance, price);
        
        // Add payment to the registry treasury
        balance::join(&mut registry.treasury, paid_balance);
        
        // Get current time
        let now_seconds = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        
        // Calculate expiration (now + duration in seconds)
        let expires_at = now_seconds + (duration_epochs * SECONDS_PER_DAY * 30); // Approximate an epoch as 30 days
        
        // Create the profile object
        let profile_picture = if (vector::length(&profile_picture_url) > 0) {
            option::some(url::new_unsafe_from_bytes(profile_picture_url))
        } else {
            option::none()
        };
        
        let cover_photo = if (vector::length(&cover_photo_url) > 0) {
            option::some(url::new_unsafe_from_bytes(cover_photo_url))
        } else {
            option::none()
        };
        
        let email_option = if (string::length(&email) > 0) {
            option::some(email)
        } else {
            option::none()
        };
        
        let display_name_option = if (string::length(&display_name) > 0) {
            option::some(display_name)
        } else {
            option::none()
        };
        
        let mut profile = Profile {
            id: object::new(ctx),
            display_name: display_name_option,
            bio,
            profile_picture,
            cover_photo,
            email: email_option,
            created_at: now,
            owner,
        };

        // Get the profile ID
        let profile_id = object::uid_to_address(&profile.id);
        
        // Store the username directly on the profile
        dynamic_field::add(&mut profile.id, USERNAME_FIELD, username);
        dynamic_field::add(&mut profile.id, USERNAME_EXPIRY_FIELD, expires_at);
        dynamic_field::add(&mut profile.id, USERNAME_REGISTERED_AT_FIELD, now_seconds);
        
        // Add to registry mappings
        table::add(&mut registry.usernames, username, profile_id);
        table::add(&mut registry.address_profiles, owner, profile_id);
        
        // Extract display name value for the event (if available)
        let display_name_value = if (option::is_some(&profile.display_name)) {
            let name_copy = *option::borrow(&profile.display_name);
            name_copy
        } else {
            string::utf8(b"")
        };
        
        // Emit profile creation event
        event::emit(ProfileCreatedEvent {
            profile_id,
            display_name: display_name_value,
            username: option::some(username),
            has_profile_picture: option::is_some(&profile.profile_picture),
            has_cover_photo: option::is_some(&profile.cover_photo),
            has_email: option::is_some(&profile.email),
            owner,
        });
        
        // Emit username registration event
        event::emit(UsernameRegisteredEvent {
            profile_id,
            username,
            owner,
            expires_at,
            registered_at: now_seconds
        });

        // Transfer profile to owner
        transfer::transfer(profile, owner);
    }

    /// Transfer a profile with its username to a new owner 
    /// The username stays with the profile, and the transfer updates registry mappings
    public entry fun transfer_profile(
        registry: &mut UsernameRegistry,
        mut profile: Profile,
        new_owner: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Verify sender is the owner
        assert!(profile.owner == sender, EUnauthorized);

        // Verify the profile has a username (it must have one)
        assert!(dynamic_field::exists_(&profile.id, USERNAME_FIELD), EProfileMustHaveUsername);
        
        // Get the profile ID
        let profile_id = object::uid_to_address(&profile.id);
        
        // Get the username
        let username = *dynamic_field::borrow<vector<u8>, String>(&profile.id, USERNAME_FIELD);
        
        // Update registry mappings
        table::remove(&mut registry.address_profiles, sender);
        table::add(&mut registry.address_profiles, new_owner, profile_id);
        
        // Update the profile owner
        profile.owner = new_owner;
        
        // Get current time
        let now_seconds = tx_context::epoch(ctx);
        
        // Emit username transferred event
        event::emit(UsernameTransferredEvent {
            profile_id,
            username,
            old_owner: sender,
            new_owner,
            transferred_at: now_seconds
        });
        
        // Transfer profile to new owner
        transfer::public_transfer(profile, new_owner);
    }

    /// Renew a username for additional time
    public entry fun renew_username(
        registry: &mut UsernameRegistry,
        profile: &mut Profile,
        duration_epochs: u64, 
        payment: &mut Coin<MYS>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Verify sender is the owner
        assert!(profile.owner == sender, EUnauthorized);
        
        // Verify duration is valid
        assert!(duration_epochs > 0, EInvalidUsername);
        
        // Verify the profile has a username
        assert!(dynamic_field::exists_(&profile.id, USERNAME_FIELD), EProfileMustHaveUsername);
        
        // Get the username
        let username = *dynamic_field::borrow<vector<u8>, String>(&profile.id, USERNAME_FIELD);
        let username_length = string::length(&username);
        
        // Calculate price for renewal
        let price = calculate_price(username_length, duration_epochs);
        
        // Ensure sufficient payment
        let payment_value = coin::value(payment);
        assert!(payment_value >= price, EInsufficientPayment);
        
        // Deduct payment
        let payment_balance = coin::balance_mut(payment);
        let paid_balance = balance::split(payment_balance, price);
        
        // Add payment to the registry treasury
        balance::join(&mut registry.treasury, paid_balance);
        
        // Get current expiration
        let current_expiry = *dynamic_field::borrow<vector<u8>, u64>(&profile.id, USERNAME_EXPIRY_FIELD);
        
        // Calculate new expiration (extend by duration)
        let new_expiry = current_expiry + (duration_epochs * SECONDS_PER_DAY * 30);
        
        // Update expiration
        *dynamic_field::borrow_mut<vector<u8>, u64>(&mut profile.id, USERNAME_EXPIRY_FIELD) = new_expiry;
    }

    /// Update profile information, keeping the same username
    public entry fun update_profile(
        profile: &mut Profile,
        new_display_name: String,
        new_bio: String,
        new_profile_picture_url: vector<u8>,
        new_cover_photo_url: vector<u8>,
        new_email: String,
        ctx: &mut TxContext
    ) {
        assert!(profile.owner == tx_context::sender(ctx), EUnauthorized);

        // Set display name if provided, otherwise keep existing
        if (string::length(&new_display_name) > 0) {
            profile.display_name = option::some(new_display_name);
        };
        
        profile.bio = new_bio;
        
        if (vector::length(&new_profile_picture_url) > 0) {
            profile.profile_picture = option::some(url::new_unsafe_from_bytes(new_profile_picture_url));
        };
        
        if (vector::length(&new_cover_photo_url) > 0) {
            profile.cover_photo = option::some(url::new_unsafe_from_bytes(new_cover_photo_url));
        };
        
        if (string::length(&new_email) > 0) {
            profile.email = option::some(new_email);
        };

        // Get current username
        let username_option = if (dynamic_field::exists_(&profile.id, USERNAME_FIELD)) {
            option::some(*dynamic_field::borrow<vector<u8>, String>(&profile.id, USERNAME_FIELD))
        } else {
            option::none()
        };

        event::emit(ProfileUpdatedEvent {
            profile_id: object::uid_to_address(&profile.id),
            display_name: profile.display_name,
            username: username_option,
            has_profile_picture: option::is_some(&profile.profile_picture),
            has_cover_photo: option::is_some(&profile.cover_photo),
            has_email: option::is_some(&profile.email),
            owner: profile.owner,
        });
    }
    
    /// Change username of an existing profile (requires payment)
    public entry fun change_username(
        registry: &mut UsernameRegistry,
        profile: &mut Profile,
        new_username: String,
        payment: &mut Coin<MYS>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Verify sender is the owner
        assert!(profile.owner == sender, EUnauthorized);
        
        // Verify the profile has a username
        assert!(dynamic_field::exists_(&profile.id, USERNAME_FIELD), EProfileMustHaveUsername);
        
        // Validate the new username
        let username_bytes = string::as_bytes(&new_username);
        let username_length = vector::length(username_bytes);
        
        // Name length validation - between 2 and 50 characters
        assert!(username_length >= 2 && username_length <= 50, EInvalidUsername);
        
        // Check if name is reserved
        assert!(!is_reserved_name(&new_username), EReservedName);
        
        // Check that the new username isn't already registered
        assert!(!table::contains(&registry.usernames, new_username), EUsernameNotAvailable);
        
        // Use a default 1-year duration (12 epochs)
        let duration_epochs = 12;
        
        // Calculate price for the new username
        let price = calculate_price(username_length, duration_epochs);
        
        // Ensure sufficient payment
        let payment_value = coin::value(payment);
        assert!(payment_value >= price, EInsufficientPayment);
        
        // Deduct payment
        let payment_balance = coin::balance_mut(payment);
        let paid_balance = balance::split(payment_balance, price);
        
        // Add payment to the registry treasury
        balance::join(&mut registry.treasury, paid_balance);
        
        // Get current time
        let now_seconds = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        
        // Calculate expiration (now + duration in seconds)
        let expires_at = now_seconds + (duration_epochs * SECONDS_PER_DAY * 30); // Approximate an epoch as 30 days
        
        // Get the profile ID
        let profile_id = object::uid_to_address(&profile.id);
        
        // Get the old username
        let old_username = *dynamic_field::borrow<vector<u8>, String>(&profile.id, USERNAME_FIELD);
        
        // Update registry mappings for the old username
        table::remove(&mut registry.usernames, old_username);
        
        // Store the new username on the profile
        *dynamic_field::borrow_mut<vector<u8>, String>(&mut profile.id, USERNAME_FIELD) = new_username;
        *dynamic_field::borrow_mut<vector<u8>, u64>(&mut profile.id, USERNAME_EXPIRY_FIELD) = expires_at;
        *dynamic_field::borrow_mut<vector<u8>, u64>(&mut profile.id, USERNAME_REGISTERED_AT_FIELD) = now_seconds;
        
        // Add new mapping to the registry
        table::add(&mut registry.usernames, new_username, profile_id);
        
        // Emit username updated event
        event::emit(UsernameUpdatedEvent {
            profile_id,
            old_username,
            new_username,
            owner: profile.owner
        });
    }

    /// Admin function to revoke a username
    public entry fun admin_revoke_username(
        registry: &mut UsernameRegistry,
        username: String,
        reason: String,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Verify sender is an admin
        assert!(is_admin(registry, sender), ENotAdmin);
        
        // Check if username exists
        assert!(table::contains(&registry.usernames, username), EUsernameNotRegistered);
        
        // Get the profile ID for this username
        let profile_id = *table::borrow(&registry.usernames, username);
        
        // Remove from registry
        table::remove(&mut registry.usernames, username);
        
        // Note: In a full implementation, you would also need to update the profile
        // to remove or replace the username, but since we can't access it directly here,
        // this function is limited to just removing the registry entry.
        // The admin would need to do additional steps to fully handle the revocation.
    }

    // === Accessor functions ===

    /// Get the display name of a profile
    public fun display_name(profile: &Profile): Option<String> {
        profile.display_name
    }

    /// Get the bio of a profile
    public fun bio(profile: &Profile): String {
        profile.bio
    }

    /// Get the profile picture URL of a profile
    public fun profile_picture(profile: &Profile): &Option<Url> {
        &profile.profile_picture
    }
    
    /// Get the cover photo URL of a profile
    public fun cover_photo(profile: &Profile): &Option<Url> {
        &profile.cover_photo
    }
    
    /// Get the email of a profile
    public fun email(profile: &Profile): &Option<String> {
        &profile.email
    }

    /// Get the creation timestamp of a profile
    public fun created_at(profile: &Profile): u64 {
        profile.created_at
    }

    /// Get the owner of a profile
    public fun owner(profile: &Profile): address {
        profile.owner
    }

    /// Get the ID of a profile
    public fun id(profile: &Profile): &UID {
        &profile.id
    }
    
    /// Check if a profile has a username
    public fun has_username(profile: &Profile): bool {
        dynamic_field::exists_(&profile.id, USERNAME_FIELD)
    }
    
    /// Get the username string for a profile
    public fun username(profile: &Profile): Option<String> {
        if (dynamic_field::exists_(&profile.id, USERNAME_FIELD)) {
            option::some(*dynamic_field::borrow<vector<u8>, String>(&profile.id, USERNAME_FIELD))
        } else {
            option::none()
        }
    }
    
    /// Get the username expiration time
    public fun username_expiry(profile: &Profile): Option<u64> {
        if (dynamic_field::exists_(&profile.id, USERNAME_EXPIRY_FIELD)) {
            option::some(*dynamic_field::borrow<vector<u8>, u64>(&profile.id, USERNAME_EXPIRY_FIELD))
        } else {
            option::none()
        }
    }
    
    /// Get the username registration time
    public fun username_registered_at(profile: &Profile): Option<u64> {
        if (dynamic_field::exists_(&profile.id, USERNAME_REGISTERED_AT_FIELD)) {
            option::some(*dynamic_field::borrow<vector<u8>, u64>(&profile.id, USERNAME_REGISTERED_AT_FIELD))
        } else {
            option::none()
        }
    }
    
    /// Lookup profile ID by username in the registry
    public fun lookup_profile_by_username(registry: &UsernameRegistry, username: String): Option<address> {
        if (table::contains(&registry.usernames, username)) {
            option::some(*table::borrow(&registry.usernames, username))
        } else {
            option::none()
        }
    }
    
    /// Lookup profile ID by owner address
    public fun lookup_profile_by_owner(registry: &UsernameRegistry, owner: address): Option<address> {
        if (table::contains(&registry.address_profiles, owner)) {
            option::some(*table::borrow(&registry.address_profiles, owner))
        } else {
            option::none()
        }
    }
}