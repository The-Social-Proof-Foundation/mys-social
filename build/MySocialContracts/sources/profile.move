// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Profile module for the MySocial network
/// Handles user identity, profile creation, management, and username registration
#[allow(unused_const, duplicate_alias, unused_use, unused_variable, implicit_const_copy, unused_let_mut)]
module social_contracts::profile {
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    use std::ascii;
    
    use mys::object::{Self, UID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer;
    use mys::url::{Self, Url};
    use mys::dynamic_field;
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::balance::{Self, Balance};
    use mys::mys::MYS;
    use mys::package::{Self, Publisher};
    use social_contracts::upgrade;

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
    const ENotAuthorizedService: u64 = 12;
    // New error codes for profile offers
    const EOfferAlreadyExists: u64 = 13;
    const EOfferDoesNotExist: u64 = 14;
    const ECannotOfferOwnProfile: u64 = 15;
    const EInsufficientTokens: u64 = 16;
    const EUnauthorizedOfferAction: u64 = 17;
    const EOfferBelowMinimum: u64 = 18;
    const PROFILE_SALE_FEE_BPS: u64 = 500;

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

    /// Field names for dynamic fields
    const USERNAME_FIELD: vector<u8> = b"username";
    // Field name for offers
    const OFFERS_FIELD: vector<u8> = b"profile_offers";

    /// Social Platform Treasury that receives fees from profile sales
    public struct PlatformTreasury has key {
        id: UID,
        /// Treasury address that receives fees
        treasury_address: address,
    }

    /// Username Registry that stores mappings between usernames and profiles
    public struct UsernameRegistry has key {
        id: UID,
        // Maps username string to profile ID
        usernames: Table<String, address>,
        // Maps addresses (owners) to their profile IDs
        address_profiles: Table<address, address>,
        // Version of the registry, allows for controlled upgrades
        version: u64,
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
        /// Creation timestamp
        created_at: u64,
        /// Profile owner address
        owner: address,
        /// Birthdate as encrypted string (optional)
        birthdate: Option<String>,
        /// Current location as encrypted string (optional)
        current_location: Option<String>,
        /// Raised location as encrypted string (optional)
        raised_location: Option<String>,
        /// Phone number as encrypted string (optional)
        phone: Option<String>,
        /// Email as encrypted string (optional)
        email: Option<String>,
        /// Gender as encrypted string (optional)
        gender: Option<String>,
        /// Political view as encrypted string (optional)
        political_view: Option<String>,
        /// Religion as encrypted string (optional)
        religion: Option<String>,
        /// Education as encrypted string (optional)
        education: Option<String>,
        /// Website as encrypted string (optional)
        website: Option<String>,
        /// Primary language as encrypted string (optional)
        primary_language: Option<String>,
        /// Relationship status as encrypted string (optional)
        relationship_status: Option<String>,
        /// X/Twitter username as encrypted string (optional)
        x_username: Option<String>,
        /// Mastodon username as encrypted string (optional)
        mastodon_username: Option<String>,
        /// Facebook username as encrypted string (optional)
        facebook_username: Option<String>,
        /// Reddit username as encrypted string (optional)
        reddit_username: Option<String>,
        /// GitHub username as encrypted string (optional)
        github_username: Option<String>,
        /// Last updated timestamp for profile data
        last_updated: u64,
        /// Number of followers
        followers_count: u64,
        /// Number of profiles this user is following
        following_count: u64,
        /// Number of posts created by this profile
        post_count: u64,
        /// Total amount of tips received
        tips_received: u64,
        /// Minimum offer amount in MYSO tokens the owner is willing to accept (optional)
        min_offer_amount: Option<u64>,
    }

    // === Events ===

    /// Profile created event
    public struct ProfileCreatedEvent has copy, drop {
        profile_id: address,
        display_name: String,
        username: Option<String>,
        bio: String,
        profile_picture: Option<String>,
        cover_photo: Option<String>,
        owner: address,
        created_at: u64,
    }

    /// Profile updated event with all profile details
    public struct ProfileUpdatedEvent has copy, drop {
        profile_id: address,
        display_name: Option<String>,
        username: Option<String>,
        bio: String,
        profile_picture: Option<String>,
        cover_photo: Option<String>,
        owner: address,
        updated_at: u64,
        // Sensitive fields (all encrypted client-side)
        birthdate: Option<String>,
        current_location: Option<String>,
        raised_location: Option<String>,
        phone: Option<String>,
        email: Option<String>,
        gender: Option<String>,
        political_view: Option<String>,
        religion: Option<String>,
        education: Option<String>,
        website: Option<String>,
        primary_language: Option<String>,
        relationship_status: Option<String>,
        x_username: Option<String>,
        mastodon_username: Option<String>,
        facebook_username: Option<String>,
        reddit_username: Option<String>,
        github_username: Option<String>,
        min_offer_amount: Option<u64>,
    }

    /// Event emitted when an offer is created for a profile
    public struct ProfileOfferCreatedEvent has copy, drop {
        profile_id: address,
        offeror: address,
        amount: u64,
        created_at: u64,
    }

    /// Event emitted when an offer is accepted
    public struct ProfileOfferAcceptedEvent has copy, drop {
        profile_id: address,
        offeror: address,
        previous_owner: address,
        amount: u64,
        accepted_at: u64,
    }

    /// Event emitted when an offer is rejected or revoked
    public struct ProfileOfferRejectedEvent has copy, drop {
        profile_id: address,
        offeror: address,
        rejected_by: address,
        amount: u64,
        rejected_at: u64,
        is_revoked: bool,
    }

    /// Represents an offer to purchase a profile
    public struct ProfileOffer has store {
        offeror: address,
        amount: u64,
        created_at: u64,
        locked_myso: Balance<MYS>,
    }

    /// Event emitted when a fee is collected from a profile sale
    public struct ProfileSaleFeeEvent has copy, drop {
        profile_id: address,
        offeror: address,
        previous_owner: address,
        sale_amount: u64,
        fee_amount: u64,
        fee_recipient: address,
        timestamp: u64,
    }

    /// Module initializer to create the username registry
    fun init(ctx: &mut TxContext) {
        // Import current version from upgrade module
        let current_version = upgrade::current_version();
        
        let registry = UsernameRegistry {
            id: object::new(ctx),
            usernames: table::new(ctx),
            address_profiles: table::new(ctx),
            version: current_version,
        };
        
        // Create the platform treasury owned by the contract deployer
        let treasury = PlatformTreasury {
            id: object::new(ctx),
            treasury_address: tx_context::sender(ctx),
        };
        
        // Share the registry to make it globally accessible
        transfer::share_object(registry);
        
        // Share the treasury to make it globally accessible
        transfer::share_object(treasury);
    }

    // === Username Management Functions ===

    /// Check if a name is reserved and cannot be registered
    public fun is_reserved_name(name: &String): bool {
        // Convert name string to lowercase for comparison
        let name_bytes = string::as_bytes(name);
        let lowercase_name = to_lowercase_bytes(name_bytes);
        
        // Make a local copy of RESERVED_NAMES to avoid implicit copies
        let reserved_names = RESERVED_NAMES;
        let reserved_count = vector::length(&reserved_names);
        
        let mut i = 0;
        while (i < reserved_count) {
            let reserved = *vector::borrow(&reserved_names, i);
            
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

    /// Convert an ASCII String to a String
    fun ascii_to_string(ascii_str: ascii::String): String {
        string::utf8(ascii::into_bytes(ascii_str))
    }

    // === Profile Creation and Management ===

    /// Create a new profile with a required username
    /// This is the main entry point for new users, combining profile and username creation
    public entry fun create_profile(
        registry: &mut UsernameRegistry,
        display_name: String,
        username: String,
        bio: String,
        profile_picture_url: vector<u8>,
        cover_photo_url: vector<u8>,
        ctx: &mut TxContext
    ) {
        // Check version compatibility
        assert!(registry.version == upgrade::current_version(), 1);
        
        let owner = tx_context::sender(ctx);
        let now = tx_context::epoch(ctx);

        // Check that the sender doesn't already have a profile
        assert!(!table::contains(&registry.address_profiles, owner), EProfileAlreadyExists);
        
        // Validate the username
        let username_bytes = string::as_bytes(&username);
        let username_length = vector::length(username_bytes);
        
        // Username length validation - between 2 and 50 characters
        assert!(username_length >= 2 && username_length <= 50, EInvalidUsername);
        
        // Check if username is reserved in the hard coded list
        assert!(!is_reserved_name(&username), EReservedName);
        
        // Check that the username isn't already registered
        assert!(!table::contains(&registry.usernames, username), EUsernameNotAvailable);
        
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
            created_at: now,
            owner,
            birthdate: option::none(),
            current_location: option::none(),
            raised_location: option::none(),
            phone: option::none(),
            email: option::none(),
            gender: option::none(),
            political_view: option::none(),
            religion: option::none(),
            education: option::none(),
            website: option::none(),
            primary_language: option::none(),
            relationship_status: option::none(),
            x_username: option::none(),
            mastodon_username: option::none(),
            facebook_username: option::none(),
            reddit_username: option::none(),
            github_username: option::none(),
            last_updated: now,
            followers_count: 0,
            following_count: 0,
            post_count: 0,
            tips_received: 0,
            min_offer_amount: option::none(),
        };
        
        // Get the profile ID
        let profile_id = object::uid_to_address(&profile.id);
        
        // Store the username directly on the profile
        // We'll create the authorized_services table only when needed (lazy initialization)
        if (dynamic_field::exists_(&profile.id, USERNAME_FIELD)) {
            // This should never happen but we check as a safeguard
            abort EProfileCreateFailed
        };
        dynamic_field::add(&mut profile.id, USERNAME_FIELD, username);
        
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
        
        // Convert URL to String for events
        let profile_picture_string = if (option::is_some(&profile.profile_picture)) {
            let url = option::borrow(&profile.profile_picture);
            option::some(ascii_to_string(url::inner_url(url)))
        } else {
            option::none()
        };
        
        // Convert URL to String for events
        let cover_photo_string = if (option::is_some(&profile.cover_photo)) {
            let url = option::borrow(&profile.cover_photo);
            option::some(ascii_to_string(url::inner_url(url)))
        } else {
            option::none()
        };
        
        // Emit profile creation event
        event::emit(ProfileCreatedEvent {
            profile_id,
            display_name: display_name_value,
            username: option::some(username),
            bio: profile.bio,
            profile_picture: profile_picture_string,
            cover_photo: cover_photo_string,
            owner,
            created_at: tx_context::epoch(ctx),
        });

        // Transfer profile to owner
        transfer::transfer(profile, owner);
    }

    /// Transfer a profile to a new owner
    /// The username stays with the profile, and the transfer updates registry mappings
    public entry fun transfer_profile(
        registry: &mut UsernameRegistry,
        mut profile: Profile,
        new_owner: address,
        ctx: &mut TxContext
    ) {
        // Check version compatibility
        assert!(registry.version == upgrade::current_version(), 1);
        
        let sender = tx_context::sender(ctx);
        
        // Verify sender is the owner
        assert!(profile.owner == sender, EUnauthorized);
        
        // Get the profile ID
        let profile_id = object::uid_to_address(&profile.id);
        
        // Update registry mappings
        table::remove(&mut registry.address_profiles, sender);
        
        // Check if the offeror already has a profile in the registry
        // If so, remove it before adding the new mapping (allows profile swapping)
        if (table::contains(&registry.address_profiles, new_owner)) {
            table::remove(&mut registry.address_profiles, new_owner);
        };
        
        table::add(&mut registry.address_profiles, new_owner, profile_id);
        
        // Update the profile owner
        profile.owner = new_owner;
        
        // Emit a comprehensive profile updated event to indicate ownership change
        event::emit(ProfileUpdatedEvent {
            profile_id,
            display_name: profile.display_name,
            username: if (dynamic_field::exists_(&profile.id, USERNAME_FIELD)) {
                option::some(*dynamic_field::borrow<vector<u8>, String>(&profile.id, USERNAME_FIELD))
            } else {
                option::none()
            },
            bio: profile.bio,
            profile_picture: if (option::is_some(&profile.profile_picture)) {
                let url = option::borrow(&profile.profile_picture);
                option::some(ascii_to_string(url::inner_url(url)))
            } else {
                option::none()
            },
            cover_photo: if (option::is_some(&profile.cover_photo)) {
                let url = option::borrow(&profile.cover_photo);
                option::some(ascii_to_string(url::inner_url(url)))
            } else {
                option::none()
            },
            owner: new_owner,
            updated_at: tx_context::epoch(ctx),
            // Include all sensitive fields
            birthdate: profile.birthdate,
            current_location: profile.current_location,
            raised_location: profile.raised_location,
            phone: profile.phone,
            email: profile.email,
            gender: profile.gender,
            political_view: profile.political_view,
            religion: profile.religion,
            education: profile.education,
            website: profile.website,
            primary_language: profile.primary_language,
            relationship_status: profile.relationship_status,
            x_username: profile.x_username,
            mastodon_username: profile.mastodon_username,
            facebook_username: profile.facebook_username,
            reddit_username: profile.reddit_username,
            github_username: profile.github_username,
            min_offer_amount: profile.min_offer_amount,
        });
        
        // Transfer profile to new owner
        transfer::public_transfer(profile, new_owner);
    }

    /// Only the profile owner can update profile information
    /// Authorized services (via authorize_read_service) can only read data, never modify it
    public entry fun update_profile(
        profile: &mut Profile,
        // Basic profile fields
        new_display_name: String,
        new_bio: String,
        new_profile_picture_url: vector<u8>,
        new_cover_photo_url: vector<u8>,
        // Sensitive profile fields (all optional)
        birthdate: Option<String>,
        current_location: Option<String>,
        raised_location: Option<String>,
        phone: Option<String>,
        email: Option<String>,
        gender: Option<String>,
        political_view: Option<String>,
        religion: Option<String>,
        education: Option<String>,
        website: Option<String>,
        primary_language: Option<String>,
        relationship_status: Option<String>,
        x_username: Option<String>,
        mastodon_username: Option<String>,
        facebook_username: Option<String>,
        reddit_username: Option<String>,
        github_username: Option<String>,
        min_offer_amount: Option<u64>,
        ctx: &mut TxContext
    ) {
        // Verify sender is the owner
        assert!(profile.owner == tx_context::sender(ctx), EUnauthorized);
        
        // Get current timestamp
        let now = tx_context::epoch(ctx);

        // Update basic profile information
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

        // Update sensitive profile details if provided
        if (option::is_some(&birthdate)) {
            profile.birthdate = birthdate;
        };
        
        if (option::is_some(&current_location)) {
            profile.current_location = current_location;
        };
        
        if (option::is_some(&raised_location)) {
            profile.raised_location = raised_location;
        };
        
        if (option::is_some(&phone)) {
            profile.phone = phone;
        };
        
        if (option::is_some(&email)) {
            profile.email = email;
        };
        
        if (option::is_some(&gender)) {
            profile.gender = gender;
        };
        
        if (option::is_some(&political_view)) {
            profile.political_view = political_view;
        };
        
        if (option::is_some(&religion)) {
            profile.religion = religion;
        };
        
        if (option::is_some(&education)) {
            profile.education = education;
        };
        
        if (option::is_some(&website)) {
            profile.website = website;
        };
        
        if (option::is_some(&primary_language)) {
            profile.primary_language = primary_language;
        };
        
        if (option::is_some(&relationship_status)) {
            profile.relationship_status = relationship_status;
        };
        
        if (option::is_some(&x_username)) {
            profile.x_username = x_username;
        };
        
        if (option::is_some(&mastodon_username)) {
            profile.mastodon_username = mastodon_username;
        };
        
        if (option::is_some(&facebook_username)) {
            profile.facebook_username = facebook_username;
        };
        
        if (option::is_some(&reddit_username)) {
            profile.reddit_username = reddit_username;
        };
        
        if (option::is_some(&github_username)) {
            profile.github_username = github_username;
        };

        if (option::is_some(&min_offer_amount)) {
            profile.min_offer_amount = min_offer_amount;
        };
        
        // Update the last updated timestamp
        profile.last_updated = now;

        // Get current username
        let username_option = if (dynamic_field::exists_(&profile.id, USERNAME_FIELD)) {
            option::some(*dynamic_field::borrow<vector<u8>, String>(&profile.id, USERNAME_FIELD))
        } else {
            option::none()
        };

        // Convert URL to String for events
        let profile_picture_string = if (option::is_some(&profile.profile_picture)) {
            let url = option::borrow(&profile.profile_picture);
            option::some(ascii_to_string(url::inner_url(url)))
        } else {
            option::none()
        };
        
        // Convert URL to String for events
        let cover_photo_string = if (option::is_some(&profile.cover_photo)) {
            let url = option::borrow(&profile.cover_photo);
            option::some(ascii_to_string(url::inner_url(url)))
        } else {
            option::none()
        };

        // Emit comprehensive profile update event with all fields
        event::emit(ProfileUpdatedEvent {
            profile_id: object::uid_to_address(&profile.id),
            display_name: profile.display_name,
            username: username_option,
            bio: profile.bio,
            profile_picture: profile_picture_string,
            cover_photo: cover_photo_string,
            owner: profile.owner,
            updated_at: now,
            // Include all sensitive fields
            birthdate: profile.birthdate,
            current_location: profile.current_location,
            raised_location: profile.raised_location,
            phone: profile.phone,
            email: profile.email,
            gender: profile.gender,
            political_view: profile.political_view,
            religion: profile.religion,
            education: profile.education,
            website: profile.website,
            primary_language: profile.primary_language,
            relationship_status: profile.relationship_status,
            x_username: profile.x_username,
            mastodon_username: profile.mastodon_username,
            facebook_username: profile.facebook_username,
            reddit_username: profile.reddit_username,
            github_username: profile.github_username,
            min_offer_amount: profile.min_offer_amount,
        });
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

    /// Get the owner of a profile
    public fun owner(profile: &Profile): address {
        profile.owner
    }

    /// Get the ID of a profile
    public fun id(profile: &Profile): &UID {
        &profile.id
    }

    /// Get the last update timestamp for profile data
    public fun last_updated(profile: &Profile): u64 {
        profile.last_updated
    }

    /// Get the username string for a profile
    public fun username(profile: &Profile): Option<String> {
        if (dynamic_field::exists_(&profile.id, USERNAME_FIELD)) {
            option::some(*dynamic_field::borrow<vector<u8>, String>(&profile.id, USERNAME_FIELD))
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
    
    /// Check if an address is registered in the authorized_services table
    /// Tests if the address is in the authorized_services table
    /// Returns false if the address is not authorized or if the authorization table doesn't exist
    public fun is_authorized_service(profile: &Profile, address: address): bool {
        if (!dynamic_field::exists_(&profile.id, b"authorized_services")) {
            return false
        };
        
        let authorized_services = dynamic_field::borrow<vector<u8>, Table<address, String>>(&profile.id, b"authorized_services");
        table::contains(authorized_services, address)
    }
    
    /// Add an authorized service to a profile, initializing the table if needed
    /// Only the profile owner can authorize services
    public entry fun authorize_service(
        profile: &mut Profile, 
        service_address: address, 
        service_name: String, 
        ctx: &mut TxContext
    ) {
        // Verify the sender is the owner - only owner can authorize services
        let sender = tx_context::sender(ctx);
        assert!(profile.owner == sender, EUnauthorized);
        
        // Verify service address is not the same as owner (would be redundant)
        assert!(service_address != profile.owner, ENotAuthorizedService);
        
        // Create the table if it doesn't exist
        if (!dynamic_field::exists_(&profile.id, b"authorized_services")) {
            let authorized_services = table::new<address, String>(ctx);
            dynamic_field::add(&mut profile.id, b"authorized_services", authorized_services);
        };
        
        // Get the table and add the service
        let authorized_services = dynamic_field::borrow_mut<vector<u8>, Table<address, String>>(&mut profile.id, b"authorized_services");
        
        // Only add if not already in the table
        if (!table::contains(authorized_services, service_address)) {
            table::add(authorized_services, service_address, service_name);
        };
    }
    
    /// Remove an authorized service from a profile
    public entry fun revoke_authorization(
        profile: &mut Profile,
        service_address: address,
        ctx: &mut TxContext
    ) {
        // Verify the sender is the owner - only owner can revoke authorizations
        let sender = tx_context::sender(ctx);
        assert!(profile.owner == sender, EUnauthorized);
        
        // Check if authorized_services table exists
        if (!dynamic_field::exists_(&profile.id, b"authorized_services")) {
            return
        };
        
        // Get the table and remove the service if it exists
        let authorized_services = dynamic_field::borrow_mut<vector<u8>, Table<address, String>>(&mut profile.id, b"authorized_services");
        if (table::contains(authorized_services, service_address)) {
            table::remove(authorized_services, service_address);
        };
    }

    /// Get the ID address of a profile
    public fun get_id_address(profile: &Profile): address {
        object::uid_to_address(&profile.id)
    }

    /// Get the owner of a profile
    public fun get_owner(profile: &Profile): address {
        profile.owner
    }

    /// Get the followers count for a profile
    public fun get_followers_count(profile: &Profile): u64 {
        profile.followers_count
    }

    /// Get the post count for a profile
    public fun get_post_count(profile: &Profile): u64 {
        profile.post_count
    }

    /// Get the tips received for a profile
    public fun get_tips_received(profile: &Profile): u64 {
        profile.tips_received
    }

    /// Increment followers count (called by follow module)
    public fun increment_followers_count(profile: &mut Profile): u64 {
        profile.followers_count = profile.followers_count + 1;
        profile.followers_count
    }

    /// Decrement followers count (called by follow module)
    public fun decrement_followers_count(profile: &mut Profile): u64 {
        if (profile.followers_count > 0) {
            profile.followers_count = profile.followers_count - 1;
        };
        profile.followers_count
    }

    /// Increment post count (called by post module when creating a post)
    public fun increment_post_count(profile: &mut Profile): u64 {
        profile.post_count = profile.post_count + 1;
        profile.post_count
    }

    /// Decrement post count (called by post module when deleting a post)
    public fun decrement_post_count(profile: &mut Profile): u64 {
        if (profile.post_count > 0) {
            profile.post_count = profile.post_count - 1;
        };
        profile.post_count
    }

    /// Add tips received (called by post/comment module when tipping)
    public fun add_tips_received(profile: &mut Profile, amount: u64): u64 {
        profile.tips_received = profile.tips_received + amount;
        profile.tips_received
    }

    /// Get the following count for a profile
    public fun get_following_count(profile: &Profile): u64 {
        profile.following_count
    }

    /// Increment following count (called when this profile follows another profile)
    public fun increment_following_count(profile: &mut Profile): u64 {
        profile.following_count = profile.following_count + 1;
        profile.following_count
    }

    /// Decrement following count (called when this profile unfollows another profile)
    public fun decrement_following_count(profile: &mut Profile): u64 {
        if (profile.following_count > 0) {
            profile.following_count = profile.following_count - 1;
        };
        profile.following_count
    }

    /// Create an offer to purchase a profile
    /// Locks MYSO tokens in the offer
    public entry fun create_offer(
        registry: &mut UsernameRegistry,
        profile: &mut Profile,
        coin: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let profile_owner = profile.owner;
        let profile_id = object::uid_to_address(&profile.id);
        let now = tx_context::epoch(ctx);
        
        // Cannot offer on your own profile
        assert!(sender != profile_owner, ECannotOfferOwnProfile);
        
        // Check if there's sufficient tokens
        assert!(coin::value(coin) >= amount && amount > 0, EInsufficientTokens);
        
        // Check if the offer meets the minimum amount requirement (if set)
        if (option::is_some(&profile.min_offer_amount)) {
            let min_amount = *option::borrow(&profile.min_offer_amount);
            assert!(amount >= min_amount, EOfferBelowMinimum);
        };
        
        // Initialize offers table if it doesn't exist
        if (!dynamic_field::exists_(&profile.id, OFFERS_FIELD)) {
            let offers = table::new<address, ProfileOffer>(ctx);
            dynamic_field::add(&mut profile.id, OFFERS_FIELD, offers);
        };
        
        // Get the offers table
        let offers = dynamic_field::borrow_mut<vector<u8>, Table<address, ProfileOffer>>(&mut profile.id, OFFERS_FIELD);
        
        // Check if the sender already has an offer
        assert!(!table::contains(offers, sender), EOfferAlreadyExists);
        
        // Split tokens from the coin and convert to a balance for secure storage
        let offer_coin = coin::split(coin, amount, ctx);
        // Convert to balance to lock tokens in the offer
        let locked_myso = coin::into_balance(offer_coin);
        
        // Create and store the offer with locked tokens
        let offer = ProfileOffer {
            offeror: sender,
            amount,
            created_at: now,
            locked_myso,
        };
        
        table::add(offers, sender, offer);
        
        // Emit an event to track offer creation
        event::emit(ProfileOfferCreatedEvent {
            profile_id,
            offeror: sender,
            amount,
            created_at: now,
        });
    }
    
    /// Accept an offer to purchase a profile
    /// Transfers tokens to the profile owner and profile ownership to the offeror
    public entry fun accept_offer(
        registry: &mut UsernameRegistry,
        mut profile: Profile,
        treasury: &PlatformTreasury,
        offeror: address,
        new_main_profile: Option<address>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let profile_id = object::uid_to_address(&profile.id);
        let now = tx_context::epoch(ctx);
        
        // Verify sender is the profile owner
        assert!(profile.owner == sender, EUnauthorized);
        
        // Check if offers table exists
        assert!(dynamic_field::exists_(&profile.id, OFFERS_FIELD), EOfferDoesNotExist);
        
        // Get the offers table
        let offers = dynamic_field::borrow_mut<vector<u8>, Table<address, ProfileOffer>>(&mut profile.id, OFFERS_FIELD);
        
        // Check if the offer exists
        assert!(table::contains(offers, offeror), EOfferDoesNotExist);
        
        // Remove the offer from the table and get the locked tokens
        let ProfileOffer { offeror: _, amount, created_at: _, locked_myso } = table::remove(offers, offeror);
        
        // Calculate the fee amount (5% of the total)
        let fee_amount = (amount * PROFILE_SALE_FEE_BPS) / 10000;
        // Calculate amount to send to profile owner
        let owner_amount = amount - fee_amount;
        
        // Convert the locked balance to a coin
        let mut payment = coin::from_balance(locked_myso, ctx);
        
        // Split the fee amount to send to the treasury
        let fee_payment = coin::split(&mut payment, fee_amount, ctx);
        
        // Send the fee to the platform treasury
        transfer::public_transfer(fee_payment, treasury.treasury_address);
        
        // Send the remaining amount to the profile owner
        transfer::public_transfer(payment, sender);
        
        // Update registry mappings to reflect new ownership
        table::remove(&mut registry.address_profiles, sender);
        
        // Check if the offeror already has a profile in the registry
        // If so, remove it before adding the new mapping (allows profile swapping)
        if (table::contains(&registry.address_profiles, offeror)) {
            table::remove(&mut registry.address_profiles, offeror);
        };
        
        // Add new mapping for buyer
        table::add(&mut registry.address_profiles, offeror, profile_id);
        
        // If the seller provided a new main profile, register it as their main profile
        if (option::is_some(&new_main_profile)) {
            let new_profile_id = *option::borrow(&new_main_profile);
            // Add the new profile mapping for the seller
            table::add(&mut registry.address_profiles, sender, new_profile_id);
        };
        
        // Update the profile owner
        let previous_owner = profile.owner;
        profile.owner = offeror;
        
        // Emit an event to track offer acceptance and token transfer
        event::emit(ProfileOfferAcceptedEvent {
            profile_id,
            offeror,
            previous_owner,
            amount,
            accepted_at: now,
        });
        
        // Emit a comprehensive profile updated event to indicate ownership change
        event::emit(ProfileUpdatedEvent {
            profile_id,
            display_name: profile.display_name,
            username: if (dynamic_field::exists_(&profile.id, USERNAME_FIELD)) {
                option::some(*dynamic_field::borrow<vector<u8>, String>(&profile.id, USERNAME_FIELD))
            } else {
                option::none()
            },
            bio: profile.bio,
            profile_picture: if (option::is_some(&profile.profile_picture)) {
                let url = option::borrow(&profile.profile_picture);
                option::some(ascii_to_string(url::inner_url(url)))
            } else {
                option::none()
            },
            cover_photo: if (option::is_some(&profile.cover_photo)) {
                let url = option::borrow(&profile.cover_photo);
                option::some(ascii_to_string(url::inner_url(url)))
            } else {
                option::none()
            },
            owner: offeror,
            updated_at: now,
            // Include all sensitive fields
            birthdate: profile.birthdate,
            current_location: profile.current_location,
            raised_location: profile.raised_location,
            phone: profile.phone,
            email: profile.email,
            gender: profile.gender,
            political_view: profile.political_view,
            religion: profile.religion,
            education: profile.education,
            website: profile.website,
            primary_language: profile.primary_language,
            relationship_status: profile.relationship_status,
            x_username: profile.x_username,
            mastodon_username: profile.mastodon_username,
            facebook_username: profile.facebook_username,
            reddit_username: profile.reddit_username,
            github_username: profile.github_username,
            min_offer_amount: profile.min_offer_amount,
        });
        
        // Emit a fee event
        event::emit(ProfileSaleFeeEvent {
            profile_id,
            offeror,
            previous_owner,
            sale_amount: amount,
            fee_amount,
            fee_recipient: treasury.treasury_address,
            timestamp: now,
        });
        
        // Transfer the profile object to the new owner
        transfer::public_transfer(profile, offeror);
    }
    
    /// Reject or revoke an offer on a profile
    /// Can be called by the profile owner to reject or the offeror to revoke
    /// Returns locked MYSO tokens to the offeror
    public entry fun reject_or_revoke_offer(
        registry: &mut UsernameRegistry,
        profile: &mut Profile,
        offeror: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let profile_id = object::uid_to_address(&profile.id);
        let now = tx_context::epoch(ctx);
        
        // Check if offers table exists
        assert!(dynamic_field::exists_(&profile.id, OFFERS_FIELD), EOfferDoesNotExist);
        
        // Get the offers table
        let offers = dynamic_field::borrow_mut<vector<u8>, Table<address, ProfileOffer>>(&mut profile.id, OFFERS_FIELD);
        
        // Check if the offer exists
        assert!(table::contains(offers, offeror), EOfferDoesNotExist);
        
        // Verify sender is either the profile owner or the offeror
        assert!(profile.owner == sender || offeror == sender, EUnauthorizedOfferAction);
        
        // Remove the offer from the table and get the locked tokens
        let ProfileOffer { offeror, amount, created_at: _, locked_myso } = table::remove(offers, offeror);
        
        // Convert the locked balance back to a coin and return to the offeror
        // This unlocks the tokens and returns them to the original offeror
        let refund = coin::from_balance(locked_myso, ctx);
        transfer::public_transfer(refund, offeror);
        
        // Determine if this is a rejection (by owner) or revocation (by offeror)
        let is_revoked = offeror == sender;
        
        // Emit an event to track offer rejection/revocation and token return
        event::emit(ProfileOfferRejectedEvent {
            profile_id,
            offeror,
            rejected_by: sender,
            amount,
            rejected_at: now,
            is_revoked,
        });
    }

    /// Check if a profile has an offer from a specific address
    public fun has_offer_from(profile: &Profile, offeror: address): bool {
        if (!dynamic_field::exists_(&profile.id, OFFERS_FIELD)) {
            return false
        };
        
        let offers = dynamic_field::borrow<vector<u8>, Table<address, ProfileOffer>>(&profile.id, OFFERS_FIELD);
        table::contains(offers, offeror)
    }
    
    /// Check if a profile has any active offers
    public fun has_offers(profile: &Profile): bool {
        if (!dynamic_field::exists_(&profile.id, OFFERS_FIELD)) {
            return false
        };
        
        let offers = dynamic_field::borrow<vector<u8>, Table<address, ProfileOffer>>(&profile.id, OFFERS_FIELD);
        table::length(offers) > 0
    }

    /// Get the treasury address from the PlatformTreasury
    public fun get_treasury_address(treasury: &PlatformTreasury): address {
        treasury.treasury_address
    }

    // Accessor for version field
    public fun version(registry: &UsernameRegistry): u64 {
        registry.version
    }

    // Mutable accessor for version field (only for upgrade module)
    public fun borrow_version_mut(registry: &mut UsernameRegistry): &mut u64 {
        &mut registry.version
    }

    /// Migrate the registry to a new version
    /// Only callable by the admin with the AdminCap
    public entry fun migrate_registry(
        registry: &mut UsernameRegistry,
        _: &upgrade::AdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        
        // Verify this is an upgrade (new version > current version)
        assert!(registry.version < current_version, 1);
        
        // Remember old version and update to new version
        let old_version = registry.version;
        registry.version = current_version;
        
        // Emit event for object migration
        let registry_id = object::id(registry);
        upgrade::emit_migration_event(
            registry_id,
            string::utf8(b"UsernameRegistry"),
            old_version,
            tx_context::sender(ctx)
        );
        
        // Any migration logic can be added here for future upgrades
    }

    #[test_only]
    /// Initialize test environment for profile module
    public fun test_init(ctx: &mut TxContext) {
        let registry = UsernameRegistry {
            id: object::new(ctx),
            usernames: table::new(ctx),
            address_profiles: table::new(ctx),
            version: 1,
        };
        
        transfer::share_object(registry);
    }

    #[test_only]
    /// Initialize the profile registry for testing
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    /// Register a test username for testing
    public fun register_username(
        registry: &mut UsernameRegistry,
        username: String,
        display_name: Option<String>,
        _profile_picture: Option<String>,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let epoch = tx_context::epoch(ctx);
        
        // Create a profile with a proper ID
        let profile = Profile {
            id: object::new(ctx),
            display_name,
            bio: string::utf8(b"Test bio"),
            profile_picture: option::none(),
            cover_photo: option::none(),
            created_at: epoch,
            owner,
            birthdate: option::none(),
            current_location: option::none(),
            raised_location: option::none(),
            phone: option::none(),
            email: option::none(),
            gender: option::none(),
            political_view: option::none(),
            religion: option::none(),
            education: option::none(),
            website: option::none(),
            primary_language: option::none(),
            relationship_status: option::none(),
            x_username: option::none(),
            mastodon_username: option::none(),
            facebook_username: option::none(),
            reddit_username: option::none(),
            github_username: option::none(),
            last_updated: epoch,
            followers_count: 0,
            post_count: 0,
            tips_received: 0,
            following_count: 0,
            min_offer_amount: option::none(),
        };
        
        // Get the profile ID and use it for registration
        let profile_id = object::uid_to_address(&profile.id);
        
        // Register the username
        table::add(&mut registry.usernames, username, profile_id);
        
        // Map owner to profile
        table::add(&mut registry.address_profiles, owner, profile_id);
        
        // Share the profile
        transfer::share_object(profile);
    }

    /// Get the minimum offer amount for a profile
    public fun min_offer_amount(profile: &Profile): &Option<u64> {
        &profile.min_offer_amount
    }

    /// Check if a profile is for sale (has a minimum offer amount set)
    public fun is_for_sale(profile: &Profile): bool {
        option::is_some(&profile.min_offer_amount)
    }
}