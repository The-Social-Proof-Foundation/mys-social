// Copyright (c) The Social Proof Foundation, LLC.
// SPDX-License-Identifier: Apache-2.0

/// Profile module for the MySocial network
/// Handles user identity, profile creation, management, and username registration

#[allow(duplicate_alias)]
module social_contracts::profile {
    use std::string::{Self, String};
    use std::ascii;
    
    use mys::{
        object::{Self, UID},
        tx_context::{Self, TxContext},
        transfer,
        dynamic_field,
        event,
        table::{Self, Table},
        coin::{Self, Coin},
        balance::{Self, Balance},
        url::{Self, Url},
        clock::{Self, Clock}
    };
    use mys::myso::MYSO;

    use social_contracts::subscription::{Self, ProfileSubscriptionService, ProfileSubscription};
    
    use social_contracts::upgrade;

    /// Error codes
    const EProfileAlreadyExists: u64 = 0;
    const EUnauthorized: u64 = 1;
    const EInvalidUsername: u64 = 2;
    const EProfileCreateFailed: u64 = 3;
    const EReservedName: u64 = 4;
    const EUsernameNotAvailable: u64 = 5;
    const ENotAuthorizedService: u64 = 6;
    // New error codes for profile offers
    const EOfferAlreadyExists: u64 = 7;
    const EOfferDoesNotExist: u64 = 8;
    const ECannotOfferOwnProfile: u64 = 9;
    const EInsufficientTokens: u64 = 10;
    const EUnauthorizedOfferAction: u64 = 11;
    const EOfferBelowMinimum: u64 = 12;
    const EBadgeNotFound: u64 = 13;
    const EBadgeAlreadyExists: u64 = 14;
    // Vesting error codes
    const EInvalidStartTime: u64 = 15;
    const ENotVestingWalletOwner: u64 = 16;
    const EOverflow: u64 = 17;

    const PROFILE_SALE_FEE_BPS: u64 = 500;

    // Fixed-point precision for curve calculations (1000 = 1.0)
    const CURVE_PRECISION: u64 = 1000;

    // Maximum u64 value for overflow protection
    const MAX_U64: u64 = 18446744073709551615;

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
    // Field for storing MyData references
    const MYDATA_FIELD: vector<u8> = b"mydata";

    /// Social Ecosystem Treasury that receives fees from profile sales
    public struct EcosystemTreasury has key {
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
        /// Instagram username as encrypted string (optional)
        instagram_username: Option<String>,
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
        /// Collection of badges assigned to the profile
        badges: vector<ProfileBadge>,
        /// Vector tracking attached MyData IDs for efficient iteration
        attached_mydata_ids: vector<address>,
        /// Paid messaging: minimum cost to send a message to this profile (optional)
        min_message_cost: Option<u64>,
        /// Paid messaging: toggle to enable/disable paid messaging
        paid_messaging_enabled: bool,
    }

    /// Profile Badge that can be assigned to profiles by platform admins/moderators
    /// These badges cannot be transferred or sold and stay with the profile
    public struct ProfileBadge has store, copy, drop {
        /// Unique identifier for the badge (platform ID + badge name)
        badge_id: String,
        /// Name of the badge
        name: String,
        /// Description of what the badge represents
        description: String,
        /// Image URL for the badge
        image_url: String,
        /// ID of the platform that issued the badge
        platform_id: address,
        /// Timestamp when the badge was issued
        issued_at: u64,
        /// Address of the admin/moderator who issued the badge
        issued_by: address,
        /// Badge type/tier (1-100), allows for badge hierarchy
        badge_type: u8,
    }



    /// Vesting Wallet contains MYSO coins that are available for claiming over time
    public struct VestingWallet has key, store {
        id: UID,
        /// Balance of MYSO coins remaining in the wallet
        balance: Balance<MYSO>,
        /// Address of the wallet owner who can claim the tokens
        owner: address,
        /// Time when the vesting started (in milliseconds)
        start_time: u64,
        /// Amount of coins that have been claimed
        claimed_amount: u64,
        /// Total duration of the vesting schedule (in milliseconds)
        duration: u64,
        /// Total amount originally vested
        total_amount: u64,
        /// Curve factor (1000 = linear, >1000 = more at end, <1000 = more at start)
        curve_factor: u64,
    }

    // === Events ===

    /// Event emitted when a badge is assigned to a profile
    public struct BadgeAssignedEvent has copy, drop {
        /// ID of the profile receiving the badge
        profile_id: address,
        /// Badge identifier
        badge_id: String,
        /// Badge name
        name: String,
        /// Platform ID that issued the badge
        platform_id: address,
        /// Admin/moderator who assigned the badge
        assigned_by: address,
        /// Timestamp when assigned
        assigned_at: u64,
        /// Badge type/tier
        badge_type: u8,
    }

    /// Event emitted when a badge is revoked from a profile
    public struct BadgeRevokedEvent has copy, drop {
        /// ID of the profile losing the badge
        profile_id: address,
        /// Badge identifier
        badge_id: String,
        /// Platform ID that issued the badge
        platform_id: address,
        /// Admin/moderator who revoked the badge
        revoked_by: address,
        /// Timestamp when revoked
        revoked_at: u64,
    }

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
        // Social media usernames
        x_username: Option<String>,
        mastodon_username: Option<String>,
        facebook_username: Option<String>,
        reddit_username: Option<String>,
        github_username: Option<String>,
        instagram_username: Option<String>,
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
        locked_myso: Balance<MYSO>,
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

    /// Event emitted when MYSO tokens are vested
    public struct TokensVestedEvent has copy, drop {
        wallet_id: address,
        owner: address,
        total_amount: u64,
        start_time: u64,
        duration: u64,
        curve_factor: u64,
        vested_at: u64,
    }

    /// Event emitted when vested tokens are claimed
    public struct TokensClaimedEvent has copy, drop {
        wallet_id: address,
        owner: address,
        claimed_amount: u64,
        remaining_balance: u64,
        claimed_at: u64,
    }
    
    /// Bootstrap initialization function - creates the username registry and treasury
    public(package) fun bootstrap_init(ctx: &mut TxContext) {
        // Import current version from upgrade module
        let current_version = upgrade::current_version();
        
        let registry = UsernameRegistry {
            id: object::new(ctx),
            usernames: table::new(ctx),
            address_profiles: table::new(ctx),
            version: current_version,
        };
        
        // Create the Ecosystem treasury owned by the contract deployer
        let treasury = EcosystemTreasury {
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
            x_username: option::none(),
            mastodon_username: option::none(),
            facebook_username: option::none(),
            reddit_username: option::none(),
            github_username: option::none(),
            instagram_username: option::none(),
            last_updated: now,
            followers_count: 0,
            following_count: 0,
            post_count: 0,
            tips_received: 0,
            min_offer_amount: option::none(),
            badges: vector::empty<ProfileBadge>(),
            attached_mydata_ids: vector::empty<address>(),
            min_message_cost: option::none(),
            paid_messaging_enabled: false,
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
            // Social media usernames
            x_username: profile.x_username,
            mastodon_username: profile.mastodon_username,
            facebook_username: profile.facebook_username,
            reddit_username: profile.reddit_username,
            github_username: profile.github_username,
            instagram_username: profile.instagram_username,
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
        // Social media usernames (all optional)
        x_username: Option<String>,
        mastodon_username: Option<String>,
        facebook_username: Option<String>,
        reddit_username: Option<String>,
        github_username: Option<String>,
        instagram_username: Option<String>,
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

        // Update social media usernames if provided
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

        if (option::is_some(&instagram_username)) {
            profile.instagram_username = instagram_username;
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
            // Social media usernames
            x_username: profile.x_username,
            mastodon_username: profile.mastodon_username,
            facebook_username: profile.facebook_username,
            reddit_username: profile.reddit_username,
            github_username: profile.github_username,
            instagram_username: profile.instagram_username,
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
        assert!(profile.followers_count <= MAX_U64 - 1, EOverflow);
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
        assert!(profile.post_count <= MAX_U64 - 1, EOverflow);
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
        assert!(profile.tips_received <= MAX_U64 - amount, EOverflow);
        profile.tips_received = profile.tips_received + amount;
        profile.tips_received
    }

    /// Get the following count for a profile
    public fun get_following_count(profile: &Profile): u64 {
        profile.following_count
    }

    /// Increment following count (called when this profile follows another profile)
    public fun increment_following_count(profile: &mut Profile): u64 {
        assert!(profile.following_count <= MAX_U64 - 1, EOverflow);
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

    /// Create a subscription service for this profile (creates separate service object)
    public entry fun create_subscription_service(
        profile: &Profile,
        monthly_fee: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == profile.owner, EUnauthorized);
        
        // Create the subscription service and share it
        subscription::create_profile_service_entry(monthly_fee, ctx);
    }

    /// Check if a viewer has a valid subscription (uses subscription module functions)
    public fun has_valid_subscription(
        subscription: &ProfileSubscription,
        service: &ProfileSubscriptionService,
        clock: &Clock,
    ): bool {
        subscription::is_subscription_valid(subscription, service, clock)
    }

    /// Attach MyData to profile for data monetization
    public entry fun attach_mydata(
        profile: &mut Profile,
        mydata_id: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == profile.owner, EUnauthorized);
        
        // Initialize table if it doesn't exist
        if (!dynamic_field::exists_(&profile.id, MYDATA_FIELD)) {
            let tbl = table::new<address, bool>(ctx);
            dynamic_field::add(&mut profile.id, MYDATA_FIELD, tbl);
        };
        
        let tbl = dynamic_field::borrow_mut<vector<u8>, Table<address, bool>>(
            &mut profile.id,
            MYDATA_FIELD,
        );
        
        // Only add if not already attached
        if (!table::contains(tbl, mydata_id)) {
            table::add(tbl, mydata_id, true);
            // Also add to the tracking vector for efficient iteration
            vector::push_back(&mut profile.attached_mydata_ids, mydata_id);
        };
    }

    /// Check if a MyData is attached to this profile
    public fun has_mydata_attached(profile: &Profile, mydata_id: address): bool {
        if (!dynamic_field::exists_(&profile.id, MYDATA_FIELD)) {
            return false
        };
        let tbl = dynamic_field::borrow<vector<u8>, Table<address, bool>>(
            &profile.id,
            MYDATA_FIELD,
        );
        table::contains(tbl, mydata_id)
    }

    /// Remove a MyData attachment from the profile
    public entry fun detach_mydata(
        profile: &mut Profile,
        mydata_id: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == profile.owner, EUnauthorized);
        
        if (!dynamic_field::exists_(&profile.id, MYDATA_FIELD)) {
            return
        };
        
        let tbl = dynamic_field::borrow_mut<vector<u8>, Table<address, bool>>(
            &mut profile.id,
            MYDATA_FIELD,
        );
        
        if (table::contains(tbl, mydata_id)) {
            table::remove(tbl, mydata_id);
            
            // Also remove from the tracking vector
            let mut i = 0;
            let len = vector::length(&profile.attached_mydata_ids);
            while (i < len) {
                if (*vector::borrow(&profile.attached_mydata_ids, i) == mydata_id) {
                    vector::remove(&mut profile.attached_mydata_ids, i);
                    break
                };
                i = i + 1;
            };
        };
    }

    /// Get all attached MyData IDs for this profile
    public fun get_attached_mydata(profile: &Profile): vector<address> {
        // Return a copy of the attached MyData IDs vector for efficient iteration
        profile.attached_mydata_ids
    }

    /// Batch attach multiple MyData to profile for gas optimization
    public entry fun batch_attach_mydata(
        profile: &mut Profile,
        mydata_ids: vector<address>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == profile.owner, EUnauthorized);
        
        // Initialize table if it doesn't exist
        if (!dynamic_field::exists_(&profile.id, MYDATA_FIELD)) {
            let tbl = table::new<address, bool>(ctx);
            dynamic_field::add(&mut profile.id, MYDATA_FIELD, tbl);
        };
        
        let tbl = dynamic_field::borrow_mut<vector<u8>, Table<address, bool>>(
            &mut profile.id,
            MYDATA_FIELD,
        );
        
        let mut i = 0;
        let len = vector::length(&mydata_ids);
        
        while (i < len) {
            let mydata_id = *vector::borrow(&mydata_ids, i);
            
            // Only add if not already attached
            if (!table::contains(tbl, mydata_id)) {
                table::add(tbl, mydata_id, true);
                vector::push_back(&mut profile.attached_mydata_ids, mydata_id);
            };
            
            i = i + 1;
        };
    }

    /// Batch detach multiple MyData from profile for gas optimization
    public entry fun batch_detach_mydata(
        profile: &mut Profile,
        mydata_ids: vector<address>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == profile.owner, EUnauthorized);
        
        if (!dynamic_field::exists_(&profile.id, MYDATA_FIELD)) {
            return
        };
        
        let tbl = dynamic_field::borrow_mut<vector<u8>, Table<address, bool>>(
            &mut profile.id,
            MYDATA_FIELD,
        );
        
        let mut i = 0;
        let len = vector::length(&mydata_ids);
        
        while (i < len) {
            let mydata_id = *vector::borrow(&mydata_ids, i);
            
            if (table::contains(tbl, mydata_id)) {
                table::remove(tbl, mydata_id);
                
                // Remove from tracking vector
                let mut j = 0;
                let vec_len = vector::length(&profile.attached_mydata_ids);
                while (j < vec_len) {
                    if (*vector::borrow(&profile.attached_mydata_ids, j) == mydata_id) {
                        vector::remove(&mut profile.attached_mydata_ids, j);
                        break
                    };
                    j = j + 1;
                };
            };
            
            i = i + 1;
        };
    }

    /// Create an offer to purchase a profile
    /// Locks MYSO tokens in the offer
    public entry fun create_offer(
        profile: &mut Profile,
        coin: &mut Coin<MYSO>,
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
        treasury: &EcosystemTreasury,
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
        
        // Convert the locked balance to a coin
        let mut payment = coin::from_balance(locked_myso, ctx);
        
        // Split the fee amount to send to the treasury
        let fee_payment = coin::split(&mut payment, fee_amount, ctx);
        
        // Send the fee to the treasury treasury
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
            // Social media usernames
            x_username: profile.x_username,
            mastodon_username: profile.mastodon_username,
            facebook_username: profile.facebook_username,
            reddit_username: profile.reddit_username,
            github_username: profile.github_username,
            instagram_username: profile.instagram_username,
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

    /// Get the treasury address from the EcosystemTreasury
    public fun get_treasury_address(treasury: &EcosystemTreasury): address {
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

    /// Migration function for the registry
    public entry fun migrate_registry(
        registry: &mut UsernameRegistry,
        _: &upgrade::UpgradeAdminCap,
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
        bootstrap_init(ctx)
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
            x_username: option::none(),
            mastodon_username: option::none(),
            facebook_username: option::none(),
            reddit_username: option::none(),
            github_username: option::none(),
            instagram_username: option::none(),
            last_updated: epoch,
            followers_count: 0,
            post_count: 0,
            tips_received: 0,
            following_count: 0,
            min_offer_amount: option::none(),
            badges: vector::empty<ProfileBadge>(),
            attached_mydata_ids: vector::empty<address>(),
            min_message_cost: option::none(),
            paid_messaging_enabled: false,
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

    /// Adds a badge to a profile - called by platform module
    /// This function trusts the caller has done authorization checks
    public fun add_badge_to_profile(
        profile: &mut Profile,
        badge_id: String,
        badge_name: String,
        badge_description: String,
        badge_image_url: String,
        platform_id: address,
        timestamp: u64,
        issuer: address,
        badge_type: u8
    ) {
        // Create the new badge
        let badge = ProfileBadge {
            badge_id: badge_id,
            name: badge_name,
            description: badge_description,
            image_url: badge_image_url,
            platform_id,
            issued_at: timestamp,
            issued_by: issuer,
            badge_type,
        };
        
        // Check if badge with same ID already exists
        let mut i = 0;
        let len = vector::length(&profile.badges);
        while (i < len) {
            let existing_badge = vector::borrow(&profile.badges, i);
            if (string::as_bytes(&existing_badge.badge_id) == string::as_bytes(&badge_id)) {
                abort EBadgeAlreadyExists
            };
            i = i + 1;
        };
        
        // Add the badge to the profile
        vector::push_back(&mut profile.badges, badge);
        
        // Emit badge assigned event
        event::emit(BadgeAssignedEvent {
            profile_id: object::uid_to_address(&profile.id),
            badge_id: badge_id,
            name: badge_name,
            platform_id,
            assigned_by: issuer,
            assigned_at: timestamp,
            badge_type,
        });
    }
    
    /// Removes a badge from a profile - called by platform module
    /// This function trusts the caller has done authorization checks
    public fun remove_badge_from_profile(
        profile: &mut Profile,
        badge_id: &String,
        platform_id: address,
        revoker: address,
        timestamp: u64
    ) {
        // Search for and remove the badge with the given ID
        let mut found = false;
        let mut i = 0;
        let len = vector::length(&profile.badges);
        
        while (i < len) {
            let badge = vector::borrow(&profile.badges, i);
            if (string::as_bytes(&badge.badge_id) == string::as_bytes(badge_id)) {
                // Ensure badge was issued by this platform
                assert!(badge.platform_id == platform_id, EUnauthorized);
                
                // Remove the badge at this index
                vector::remove(&mut profile.badges, i);
                found = true;
                
                // Emit badge revoked event
                event::emit(BadgeRevokedEvent {
                    profile_id: object::uid_to_address(&profile.id),
                    badge_id: *badge_id,
                    platform_id,
                    revoked_by: revoker,
                    revoked_at: timestamp,
                });
                
                break
            };
            i = i + 1;
        };
        
        // Make sure we found and removed the badge
        assert!(found, EBadgeNotFound);
    }

    /// Get all badges associated with a profile
    public fun get_profile_badges(profile: &Profile): vector<ProfileBadge> {
        profile.badges
    }
    
    /// Check if a profile has a specific badge
    public fun has_badge(profile: &Profile, badge_id: &String): bool {
        let mut i = 0;
        let len = vector::length(&profile.badges);
        
        while (i < len) {
            let badge = vector::borrow(&profile.badges, i);
            if (string::as_bytes(&badge.badge_id) == string::as_bytes(badge_id)) {
                return true
            };
            i = i + 1;
        };
        
        false
    }
    
    /// Get a specific badge from a profile by badge ID
    public fun get_badge(profile: &Profile, badge_id: &String): Option<ProfileBadge> {
        let mut i = 0;
        let len = vector::length(&profile.badges);
        
        while (i < len) {
            let badge = vector::borrow(&profile.badges, i);
            if (string::as_bytes(&badge.badge_id) == string::as_bytes(badge_id)) {
                return option::some(*badge)
            };
            i = i + 1;
        };
        
        option::none()
    }
    
    /// Get badges issued by a specific platform
    public fun get_platform_badges(profile: &Profile, platform_id: address): vector<ProfileBadge> {
        let mut result = vector::empty<ProfileBadge>();
        
        let mut i = 0;
        let len = vector::length(&profile.badges);
        
        while (i < len) {
            let badge = vector::borrow(&profile.badges, i);
            if (badge.platform_id == platform_id) {
                vector::push_back(&mut result, *badge);
            };
            i = i + 1;
        };
        
        result
    }
    
    /// Count the number of badges a profile has
    public fun badge_count(profile: &Profile): u64 {
        vector::length(&profile.badges)
    }

    // === Vesting Functions ===

    /// Create a new vesting wallet with MYSO tokens that vest over time with configurable curve
    /// The start time must be in the future and duration must be greater than 0
    /// curve_factor: 0 or 1000 = linear, >1000 = more tokens at end, <1000 = more tokens at start
    /// 
    /// Example Curves:
    /// Exponential (curve_factor = 2000):
    /// 25% time → ~6% tokens
    /// 50% time → ~25% tokens
    /// 75% time → ~56% tokens
    /// 100% time → 100% tokens
    /// Logarithmic (curve_factor = 500):
    /// 25% time → ~44% tokens
    /// 50% time → ~75% tokens
    /// 75% time → ~94% tokens
    /// 100% time → 100% tokens

    public entry fun vest_myso(
        coin: Coin<MYSO>,
        recipient: address,
        start_time: u64,
        duration: u64,
        curve_factor: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate that start time is in the future
        let current_time = clock::timestamp_ms(clock);
        assert!(start_time > current_time, EInvalidStartTime);

        // Validate that duration is greater than 0
        assert!(duration > 0, EInvalidStartTime);

        let total_amount = coin::value(&coin);
        assert!(total_amount > 0, EInsufficientTokens);

        // Default to linear if curve_factor is 0
        let final_curve_factor = if (curve_factor == 0) {
            CURVE_PRECISION // 1000 = linear
        } else {
            // Validate curve factor is reasonable (between 100 and 10000, i.e., 0.1x to 10x)
            assert!(curve_factor >= 100 && curve_factor <= 10000, EInvalidStartTime);
            curve_factor
        };

        // Create the vesting wallet
        let wallet = VestingWallet {
            id: object::new(ctx),
            balance: coin::into_balance(coin),
            owner: recipient,
            start_time,
            claimed_amount: 0,
            duration,
            total_amount,
            curve_factor: final_curve_factor,
        };

        let wallet_id = object::uid_to_address(&wallet.id);

        // Emit vesting event
        event::emit(TokensVestedEvent {
            wallet_id,
            owner: recipient,
            total_amount,
            start_time,
            duration,
            curve_factor: final_curve_factor,
            vested_at: current_time,
        });

        // Transfer the vesting wallet to the recipient
        transfer::public_transfer(wallet, recipient);
    }

    /// Claim vested tokens from a vesting wallet
    /// Only the wallet owner can claim tokens, and only claimable amounts
    public entry fun claim_vested_tokens(
        wallet: &mut VestingWallet,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Verify sender is the wallet owner
        assert!(wallet.owner == sender, ENotVestingWalletOwner);

        let claimable_amount = calculate_claimable(wallet, clock);
        
        // Only proceed if there are tokens to claim
        if (claimable_amount > 0) {
            // Update claimed amount
            assert!(wallet.claimed_amount <= MAX_U64 - claimable_amount, EOverflow);
            wallet.claimed_amount = wallet.claimed_amount + claimable_amount;
            
            // Create coin from the claimable balance and transfer to owner
            let claimed_coin = coin::from_balance<MYSO>(
                balance::split(&mut wallet.balance, claimable_amount),
                ctx
            );
            
            let wallet_id = object::uid_to_address(&wallet.id);
            let remaining_balance = balance::value(&wallet.balance);
            
            // Emit claim event
            event::emit(TokensClaimedEvent {
                wallet_id,
                owner: sender,
                claimed_amount: claimable_amount,
                remaining_balance,
                claimed_at: clock::timestamp_ms(clock),
            });
            
            // Transfer claimed tokens to the owner
            transfer::public_transfer(claimed_coin, sender);
        };
    }

    /// Calculate how many tokens can be claimed from a vesting wallet at the current time
    public fun claimable(wallet: &VestingWallet, clock: &Clock): u64 {
        calculate_claimable(wallet, clock)
    }

    /// Internal function to calculate claimable amount
    fun calculate_claimable(wallet: &VestingWallet, clock: &Clock): u64 {
        let current_time = clock::timestamp_ms(clock);
        
        // If vesting hasn't started yet, nothing is claimable
        if (current_time < wallet.start_time) {
            return 0
        };
        
        // If vesting period is complete, all remaining balance is claimable
        if (current_time >= wallet.start_time + wallet.duration) {
            return balance::value(&wallet.balance)
        };
        
        // Calculate progress as a percentage (0 to CURVE_PRECISION)
        let elapsed_time = current_time - wallet.start_time;
        let progress = ((elapsed_time as u128) * (CURVE_PRECISION as u128)) / (wallet.duration as u128);
        
        // Apply curve based on curve_factor
        let curved_progress = if (wallet.curve_factor == CURVE_PRECISION) {
            // Linear vesting (curve_factor = 1000)
            progress
        } else if (wallet.curve_factor > CURVE_PRECISION) {
            // Exponential curve - more tokens at the end
            // Use simplified exponential: progress^2 scaled by curve_factor
            let steepness = wallet.curve_factor - CURVE_PRECISION; // How much above linear
            let quadratic = (progress * progress) / (CURVE_PRECISION as u128);
            let linear_part = (progress * (CURVE_PRECISION as u128)) / (CURVE_PRECISION as u128);
            
            // Blend between linear and quadratic based on steepness
            (linear_part * (CURVE_PRECISION as u128) + quadratic * (steepness as u128)) / (CURVE_PRECISION as u128)
        } else {
            // Logarithmic curve - more tokens at the start
            // Use simplified square root approximation for early release
            let steepness = CURVE_PRECISION - wallet.curve_factor; // How much below linear
            let sqrt_approx = sqrt_approximation(progress * (CURVE_PRECISION as u128)) * (CURVE_PRECISION as u128) / (CURVE_PRECISION as u128);
            let linear_part = progress;
            
            // Blend between square root and linear based on steepness
            (sqrt_approx * (steepness as u128) + linear_part * (CURVE_PRECISION as u128)) / (CURVE_PRECISION as u128)
        };
        
        // Convert back to total claimable amount
        let total_claimable = ((wallet.total_amount as u128) * curved_progress) / (CURVE_PRECISION as u128);
        
        // Subtract already claimed amount to get newly claimable amount
        let newly_claimable = (total_claimable as u64) - wallet.claimed_amount;
        
        // Ensure we don't exceed the remaining balance
        let remaining_balance = balance::value(&wallet.balance);
        if (newly_claimable > remaining_balance) {
            remaining_balance
        } else {
            newly_claimable
        }
    }

    /// Simple square root approximation using Newton's method
    fun sqrt_approximation(n: u128): u128 {
        if (n == 0) return 0;
        if (n == 1) return 1;
        
        let mut x = n;
        let mut y = (x + 1) / 2;
        
        // Newton's method with limited iterations
        let mut i = 0;
        while (y < x && i < 10) {
            x = y;
            y = (x + n / x) / 2;
            i = i + 1;
        };
        
        x
    }

    /// Delete an empty vesting wallet
    /// Can only be called when the wallet balance is zero
    public entry fun delete_vesting_wallet(wallet: VestingWallet, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        
        // Verify sender is the wallet owner
        assert!(wallet.owner == sender, ENotVestingWalletOwner);
        
        let VestingWallet { 
            id, 
            balance, 
            owner: _, 
            start_time: _, 
            claimed_amount: _, 
            duration: _, 
            total_amount: _,
            curve_factor: _
        } = wallet;
        
        // Delete the wallet ID
        object::delete(id);
        
        // Destroy the empty balance
        balance::destroy_zero(balance);
    }

    // === Vesting Wallet Accessors ===

    /// Get the remaining balance in a vesting wallet
    public fun vesting_balance(wallet: &VestingWallet): u64 {
        balance::value(&wallet.balance)
    }

    /// Get the owner of a vesting wallet
    public fun vesting_owner(wallet: &VestingWallet): address {
        wallet.owner
    }

    /// Get the start time of a vesting schedule
    public fun vesting_start_time(wallet: &VestingWallet): u64 {
        wallet.start_time
    }

    /// Get the duration of a vesting schedule
    public fun vesting_duration(wallet: &VestingWallet): u64 {
        wallet.duration
    }

    /// Get the total amount originally vested
    public fun vesting_total_amount(wallet: &VestingWallet): u64 {
        wallet.total_amount
    }

    /// Get the amount already claimed from a vesting wallet
    public fun vesting_claimed_amount(wallet: &VestingWallet): u64 {
        wallet.claimed_amount
    }

    /// Get the curve factor of a vesting wallet
    public fun vesting_curve_factor(wallet: &VestingWallet): u64 {
        wallet.curve_factor
    }

    // === Paid Messaging Functions ===

    /// Set paid messaging settings for a profile (owner only)
    public entry fun set_paid_messaging_settings(
        profile: &mut Profile,
        enabled: bool,
        min_cost: Option<u64>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(profile.owner == sender, EUnauthorized);

        profile.paid_messaging_enabled = enabled;
        profile.min_message_cost = min_cost;
    }

    /// Get paid messaging settings for a profile
    public fun get_paid_messaging_settings(profile: &Profile): (bool, Option<u64>) {
        (profile.paid_messaging_enabled, profile.min_message_cost)
    }

    /// Check if a profile requires paid messages
    public fun requires_paid_message(profile: &Profile): bool {
        profile.paid_messaging_enabled && option::is_some(&profile.min_message_cost)
    }

    /// Get minimum message cost for a profile
    public fun get_min_message_cost(profile: &Profile): Option<u64> {
        profile.min_message_cost
    }

}