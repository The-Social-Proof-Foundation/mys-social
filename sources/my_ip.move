// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// MyIP module for the MySocial network
/// Manages user-owned intellectual property (IP) objects with flexible licensing options

module social_contracts::my_ip {
    use std::string::{Self, String};
    
    use mys::event;
    use mys::url::{Self, Url};
    use mys::table::{Self, Table};
    
    use social_contracts::profile::{Self, Profile};
    use social_contracts::upgrade::{Self, AdminCap};
    
    /// Error codes
    const EUnauthorized: u64 = 0;
    const EInvalidLicenseType: u64 = 1;
    const EInvalidPermission: u64 = 2;
    const ELicenseNonTransferable: u64 = 3;
    const EInvalidLicenseState: u64 = 4;
    const EWrongVersion: u64 = 5;
    const ELicenseNotRegistered: u64 = 6;
    
    /// License types
    const LICENSE_TYPE_CREATIVE_COMMONS: u8 = 0;
    const LICENSE_TYPE_TOKEN_BOUND: u8 = 1;
    const LICENSE_TYPE_CUSTOM: u8 = 2;
    
    /// License states
    const LICENSE_STATE_ACTIVE: u8 = 0;
    const LICENSE_STATE_EXPIRED: u8 = 1;
    const LICENSE_STATE_REVOKED: u8 = 2;
    
    /// Permission flags (stored as bits in a u64)
    const PERMISSION_COMMERCIAL_USE: u64 = 1 << 0;     // 1
    const PERMISSION_DERIVATIVES_ALLOWED: u64 = 1 << 1; // 2
    const PERMISSION_PUBLIC_LICENSE: u64 = 1 << 2;     // 4
    const PERMISSION_AUTHORITY_REQUIRED: u64 = 1 << 3; // 8
    const PERMISSION_SHARE_ALIKE: u64 = 1 << 4;        // 16
    const PERMISSION_REQUIRE_ATTRIBUTION: u64 = 1 << 5; // 32
    const PERMISSION_REVENUE_REDIRECT: u64 = 1 << 6;   // 64
    
    /// Social interaction permissions - for controlling post interactions
    const PERMISSION_ALLOW_COMMENTS: u64 = 1 << 10;    // 1024
    const PERMISSION_ALLOW_REACTIONS: u64 = 1 << 11;   // 2048
    const PERMISSION_ALLOW_REPOSTS: u64 = 1 << 12;     // 4096
    const PERMISSION_ALLOW_QUOTES: u64 = 1 << 13;      // 8192
    const PERMISSION_ALLOW_TIPS: u64 = 1 << 14;        // 16384
    
    /// Intellectual property object with enhanced licensing capabilities
    public struct MyIP has key, store {
        id: UID,
        /// Basic metadata
        name: String,
        description: String,
        creator: address,
        creation_time: u64,
        
        /// License properties
        license_type: u8,
        permission_flags: u64,
        license_state: u8,
        
        /// Optional fields
        proof_of_creativity_id: Option<address>,
        custom_license_uri: Option<Url>,
        revenue_recipient: Option<address>,
        transferable: bool,
        expires_at: Option<u64>,
        
        /// Version for upgrades
        version: u64,
    }
    
    /// Registry for MyIP licenses and their permissions
    public struct MyIPRegistry has key {
        id: UID,
        /// Maps license IDs to their permissions bitmap
        permissions: Table<address, u64>,
        /// Maps license IDs to their license types
        license_types: Table<address, u8>,
        /// Maps license IDs to revenue recipients (if redirected)
        revenue_recipients: Table<address, address>,
        /// Maps license IDs to license states (active, expired, revoked)
        states: Table<address, u8>,
        /// Maps license IDs to their creators
        creators: Table<address, address>,
        /// Maps license IDs to expiration timestamps
        expirations: Table<address, u64>,
        /// Version for upgrades
        version: u64,
    }
    
    /// License capability to manage licenses
    /// This capability grants permission to modify specific licenses
    public struct LicenseAdminCap has key, store {
        id: UID,
        license_id: address,
        admin: address,
    }
    
    /// Events
    
    /// Event emitted when a new license is created
    public struct LicenseCreatedEvent has copy, drop {
        license_id: address,
        creator: address,
        license_type: u8,
        permission_flags: u64,
        creation_time: u64,
    }
    
    /// Event emitted when a license is updated
    public struct LicenseUpdatedEvent has copy, drop {
        license_id: address,
        updater: address,
        old_permission_flags: u64,
        new_permission_flags: u64,
        update_time: u64,
    }
    
    /// Event emitted when a license is transferred
    public struct LicenseTransferredEvent has copy, drop {
        license_id: address,
        from: address,
        to: address,
        transfer_time: u64,
    }
    
    /// Event emitted when a license state changes
    public struct LicenseStateChangedEvent has copy, drop {
        license_id: address,
        old_state: u8,
        new_state: u8,
        changer: address,
        change_time: u64,
    }
    
    /// Event emitted when a license is linked to a post
    #[allow(unused_field)]
    public struct LicenseLinkedEvent has copy, drop {
        license_id: address,
        post_id: address,
        linker: address,
        link_time: u64,
    }
    
    /// Event emitted when a license is registered in the registry
    public struct LicenseRegisteredEvent has copy, drop {
        license_id: address,
        registry_id: address,
        creator: address,
        permission_flags: u64,
    }
    
    /// Module initialization
    fun init(ctx: &mut TxContext) {
        // Create and share the registry
        let registry = MyIPRegistry {
            id: object::new(ctx),
            permissions: table::new(ctx),
            license_types: table::new(ctx),
            revenue_recipients: table::new(ctx),
            states: table::new(ctx),
            creators: table::new(ctx),
            expirations: table::new(ctx),
            version: upgrade::current_version(),
        };
        
        // Share the registry
        transfer::share_object(registry);
    }
    
    /// Create a new IP object with license
    public fun create(
        name: String,
        description: String,
        license_type: u8,
        permission_flags: u64,
        proof_of_creativity_id: Option<address>,
        mut custom_license_uri_bytes: Option<vector<u8>>,
        revenue_recipient: Option<address>,
        transferable: bool,
        expires_at: Option<u64>,
        ctx: &mut TxContext
    ): MyIP {
        // Validate license type
        assert!(
            license_type == LICENSE_TYPE_CREATIVE_COMMONS ||
            license_type == LICENSE_TYPE_TOKEN_BOUND ||
            license_type == LICENSE_TYPE_CUSTOM,
            EInvalidLicenseType
        );
        
        // For custom licenses, require a custom URI
        if (license_type == LICENSE_TYPE_CUSTOM) {
            assert!(option::is_some(&custom_license_uri_bytes), EInvalidLicenseType);
        };
        
        // If revenue redirection is enabled, require a recipient
        if ((permission_flags & PERMISSION_REVENUE_REDIRECT) != 0) {
            assert!(option::is_some(&revenue_recipient), EInvalidPermission);
        };
        
        // Convert URI bytes to URL object if provided
        let custom_license_uri = if (option::is_some(&custom_license_uri_bytes)) {
            let uri_bytes = option::extract(&mut custom_license_uri_bytes);
            option::some(url::new_unsafe_from_bytes(uri_bytes))
        } else {
            option::none<Url>()
        };
        
        let license = MyIP {
            id: object::new(ctx),
            name,
            description,
            creator: tx_context::sender(ctx),
            creation_time: tx_context::epoch_timestamp_ms(ctx),
            license_type,
            permission_flags,
            license_state: LICENSE_STATE_ACTIVE,
            proof_of_creativity_id,
            custom_license_uri,
            revenue_recipient,
            transferable,
            expires_at,
            version: upgrade::current_version(),
        };
        
        let license_id = object::uid_to_address(&license.id);
        
        // Emit license created event
        event::emit(LicenseCreatedEvent {
            license_id,
            creator: license.creator,
            license_type: license.license_type,
            permission_flags: license.permission_flags,
            creation_time: license.creation_time,
        });
        
        license
    }
    
    /// Create and register a new IP license transferring to creator
    public entry fun create_license(
        registry: &mut MyIPRegistry,
        creator_profile: &Profile,
        name: String,
        description: String,
        license_type: u8,
        permission_flags: u64,
        proof_of_creativity_id: Option<address>,
        custom_license_uri_bytes: Option<vector<u8>>,
        revenue_recipient: Option<address>,
        transferable: bool,
        expires_at: Option<u64>,
        ctx: &mut TxContext
    ) {
        // Verify caller owns the profile
        assert!(tx_context::sender(ctx) == profile::owner(creator_profile), EUnauthorized);
        
        let license = create(
            name,
            description,
            license_type,
            permission_flags,
            proof_of_creativity_id,
            custom_license_uri_bytes,
            revenue_recipient,
            transferable,
            expires_at,
            ctx
        );
        
        // Create admin capability
        let license_id = object::uid_to_address(&license.id);
        let admin_cap = LicenseAdminCap {
            id: object::new(ctx),
            license_id,
            admin: tx_context::sender(ctx),
        };
        
        // Register in the registry
        register_license_internal(registry, &license);
        
        // Transfer license and capability to creator
        transfer::transfer(license, tx_context::sender(ctx));
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }
    
    /// Update license permissions
    public entry fun update_license_permissions(
        registry: &mut MyIPRegistry,
        license: &mut MyIP,
        admin_cap: &LicenseAdminCap,
        new_permission_flags: u64,
        ctx: &mut TxContext
    ) {
        // Verify admin capability
        let license_id = object::uid_to_address(&license.id);
        assert!(admin_cap.license_id == license_id, EUnauthorized);
        assert!(admin_cap.admin == tx_context::sender(ctx), EUnauthorized);
        
        // Verify license is active
        assert!(license.license_state == LICENSE_STATE_ACTIVE, EInvalidLicenseState);
        
        let old_flags = license.permission_flags;
        license.permission_flags = new_permission_flags;
        
        // Update in registry if present
        if (table::contains(&registry.permissions, license_id)) {
            *table::borrow_mut(&mut registry.permissions, license_id) = new_permission_flags;
            
            // Update revenue recipient info if needed
            if ((new_permission_flags & PERMISSION_REVENUE_REDIRECT) != 0) {
                if (option::is_some(&license.revenue_recipient)) {
                    let recipient = *option::borrow(&license.revenue_recipient);
                    if (table::contains(&registry.revenue_recipients, license_id)) {
                        *table::borrow_mut(&mut registry.revenue_recipients, license_id) = recipient;
                    } else {
                        table::add(&mut registry.revenue_recipients, license_id, recipient);
                    }
                }
            } else {
                // Remove revenue recipient if redirection is turned off
                if (table::contains(&registry.revenue_recipients, license_id)) {
                    table::remove(&mut registry.revenue_recipients, license_id);
                }
            }
        };
        
        // Emit license updated event
        event::emit(LicenseUpdatedEvent {
            license_id,
            updater: tx_context::sender(ctx),
            old_permission_flags: old_flags,
            new_permission_flags: new_permission_flags,
            update_time: tx_context::epoch_timestamp_ms(ctx),
        });
    }
    
    /// Update revenue recipient
    public entry fun update_revenue_recipient(
        registry: &mut MyIPRegistry,
        license: &mut MyIP,
        admin_cap: &LicenseAdminCap,
        new_recipient: address,
        ctx: &mut TxContext
    ) {
        // Verify admin capability
        let license_id = object::uid_to_address(&license.id);
        assert!(admin_cap.license_id == license_id, EUnauthorized);
        assert!(admin_cap.admin == tx_context::sender(ctx), EUnauthorized);
        
        // Verify license is active
        assert!(license.license_state == LICENSE_STATE_ACTIVE, EInvalidLicenseState);
        
        // Update recipient
        license.revenue_recipient = option::some(new_recipient);
        
        // Ensure revenue redirect flag is set
        license.permission_flags = license.permission_flags | PERMISSION_REVENUE_REDIRECT;
        
        // Update in registry if present
        if (table::contains(&registry.permissions, license_id)) {
            *table::borrow_mut(&mut registry.permissions, license_id) = license.permission_flags;
            
            // Update revenue recipient
            if (table::contains(&registry.revenue_recipients, license_id)) {
                *table::borrow_mut(&mut registry.revenue_recipients, license_id) = new_recipient;
            } else {
                table::add(&mut registry.revenue_recipients, license_id, new_recipient);
            }
        };
        
        // Emit license updated event
        event::emit(LicenseUpdatedEvent {
            license_id,
            updater: tx_context::sender(ctx),
            old_permission_flags: license.permission_flags,
            new_permission_flags: license.permission_flags,
            update_time: tx_context::epoch_timestamp_ms(ctx),
        });
    }
    
    /// Set license state (active, expired, revoked)
    public entry fun set_license_state(
        registry: &mut MyIPRegistry,
        license: &mut MyIP,
        admin_cap: &LicenseAdminCap,
        new_state: u8,
        ctx: &mut TxContext
    ) {
        // Verify admin capability
        let license_id = object::uid_to_address(&license.id);
        assert!(admin_cap.license_id == license_id, EUnauthorized);
        assert!(admin_cap.admin == tx_context::sender(ctx), EUnauthorized);
        
        // Validate state
        assert!(
            new_state == LICENSE_STATE_ACTIVE ||
            new_state == LICENSE_STATE_EXPIRED ||
            new_state == LICENSE_STATE_REVOKED,
            EInvalidLicenseState
        );
        
        let old_state = license.license_state;
        license.license_state = new_state;
        
        // Update in registry if present
        if (table::contains(&registry.states, license_id)) {
            *table::borrow_mut(&mut registry.states, license_id) = new_state;
        };
        
        // Emit license state changed event
        event::emit(LicenseStateChangedEvent {
            license_id,
            old_state,
            new_state,
            changer: tx_context::sender(ctx),
            change_time: tx_context::epoch_timestamp_ms(ctx),
        });
    }
    
    /// Internal function to register a license in the registry
    fun register_license_internal(registry: &mut MyIPRegistry, license: &MyIP) {
        let license_id = object::uid_to_address(&license.id);
        
        // Store license info in registry tables
        table::add(&mut registry.permissions, license_id, license.permission_flags);
        table::add(&mut registry.license_types, license_id, license.license_type);
        table::add(&mut registry.states, license_id, license.license_state);
        table::add(&mut registry.creators, license_id, license.creator);
        
        // Add revenue recipient if set
        if (option::is_some(&license.revenue_recipient)) {
            let recipient = *option::borrow(&license.revenue_recipient);
            table::add(&mut registry.revenue_recipients, license_id, recipient);
        };
        
        // Add expiration time if set
        if (option::is_some(&license.expires_at)) {
            let expires = *option::borrow(&license.expires_at);
            table::add(&mut registry.expirations, license_id, expires);
        };
        
        // Emit license registered event
        event::emit(LicenseRegisteredEvent {
            license_id,
            registry_id: object::uid_to_address(&registry.id),
            creator: license.creator,
            permission_flags: license.permission_flags,
        });
    }
    
    /// Register an existing license in the registry (for admin use)
    public entry fun register_license(
        registry: &mut MyIPRegistry,
        license: &MyIP,
        ctx: &mut TxContext
    ) {
        // Only creator or admin can register
        assert!(tx_context::sender(ctx) == license.creator, EUnauthorized);
        
        // Register the license
        register_license_internal(registry, license);
    }
    
    /// Update a license in the registry (for keeping registry synchronized)
    public entry fun update_license_in_registry(
        registry: &mut MyIPRegistry,
        license: &MyIP,
        ctx: &mut TxContext
    ) {
        // Only creator can update
        assert!(tx_context::sender(ctx) == license.creator, EUnauthorized);
        
        let license_id = object::uid_to_address(&license.id);
        
        // Verify license is in registry
        assert!(table::contains(&registry.permissions, license_id), ELicenseNotRegistered);
        
        // Update registry information
        *table::borrow_mut(&mut registry.permissions, license_id) = license.permission_flags;
        *table::borrow_mut(&mut registry.license_types, license_id) = license.license_type;
        *table::borrow_mut(&mut registry.states, license_id) = license.license_state;
        
        // Update revenue recipient if needed
        if (option::is_some(&license.revenue_recipient)) {
            let recipient = *option::borrow(&license.revenue_recipient);
            if (table::contains(&registry.revenue_recipients, license_id)) {
                *table::borrow_mut(&mut registry.revenue_recipients, license_id) = recipient;
            } else {
                table::add(&mut registry.revenue_recipients, license_id, recipient);
            }
        } else if (table::contains(&registry.revenue_recipients, license_id)) {
            table::remove(&mut registry.revenue_recipients, license_id);
        };
        
        // Update expiration if needed
        if (option::is_some(&license.expires_at)) {
            let expires = *option::borrow(&license.expires_at);
            if (table::contains(&registry.expirations, license_id)) {
                *table::borrow_mut(&mut registry.expirations, license_id) = expires;
            } else {
                table::add(&mut registry.expirations, license_id, expires);
            }
        } else if (table::contains(&registry.expirations, license_id)) {
            table::remove(&mut registry.expirations, license_id);
        };
    }
    
    /// Transfer license to a new owner
    #[allow(lint(custom_state_change))]
    public entry fun transfer_license(
        license: MyIP,
        admin_cap: &LicenseAdminCap,
        recipient: address,
        ctx: &mut TxContext
    ) {
        // Verify admin capability and transferability
        let license_id = object::uid_to_address(&license.id);
        assert!(admin_cap.license_id == license_id, EUnauthorized);
        assert!(admin_cap.admin == tx_context::sender(ctx), EUnauthorized);
        assert!(license.transferable, ELicenseNonTransferable);
        
        // Verify license is active
        assert!(license.license_state == LICENSE_STATE_ACTIVE, EInvalidLicenseState);
        
        let sender = tx_context::sender(ctx);
        
        // Emit license transferred event
        event::emit(LicenseTransferredEvent {
            license_id,
            from: sender,
            to: recipient,
            transfer_time: tx_context::epoch_timestamp_ms(ctx),
        });
        
        // Transfer license to recipient
        transfer::transfer(license, recipient);
    }
    
    /// Transfer admin capability to a new admin
    #[allow(lint(custom_state_change))]
    public entry fun transfer_admin_cap(
        admin_cap: LicenseAdminCap,
        recipient: address,
        ctx: &mut TxContext
    ) {
        assert!(admin_cap.admin == tx_context::sender(ctx), EUnauthorized);
        transfer::transfer(admin_cap, recipient);
    }
    
    /// Set proof of creativity ID
    public entry fun set_poc_id(
        license: &mut MyIP,
        admin_cap: &LicenseAdminCap,
        poc_id: address,
        ctx: &mut TxContext
    ) {
        // Verify admin capability
        let license_id = object::uid_to_address(&license.id);
        assert!(admin_cap.license_id == license_id, EUnauthorized);
        assert!(admin_cap.admin == tx_context::sender(ctx), EUnauthorized);
        
        license.proof_of_creativity_id = option::some(poc_id);
    }
    
    // === Registry Permission Check Functions ===
    
    /// Check if a license is registered in the registry
    public fun is_registered(registry: &MyIPRegistry, license_id: address): bool {
        table::contains(&registry.permissions, license_id)
    }
    
    /// Check if a specific permission is granted for a license
    public fun registry_has_permission(registry: &MyIPRegistry, license_id: address, permission: u64, ctx: &TxContext): bool {
        if (!table::contains(&registry.permissions, license_id)) return false;
        if (!table::contains(&registry.states, license_id)) return false;
        
        // Check license state first
        let state = *table::borrow(&registry.states, license_id);
        if (state != LICENSE_STATE_ACTIVE) return false;
        
        // Check for expiration
        if (table::contains(&registry.expirations, license_id)) {
            let expires_at = *table::borrow(&registry.expirations, license_id);
            let current = tx_context::epoch_timestamp_ms(ctx);
            if (current >= expires_at) return false;
        };
        
        // Check specific permission
        let permissions = *table::borrow(&registry.permissions, license_id);
        (permissions & permission) != 0
    }
    
    /// Check if commenting is allowed (registry version)
    public fun registry_is_commenting_allowed(registry: &MyIPRegistry, license_id: address, ctx: &TxContext): bool {
        registry_has_permission(registry, license_id, PERMISSION_ALLOW_COMMENTS, ctx)
    }
    
    /// Check if reactions/likes are allowed (registry version)
    public fun registry_is_reactions_allowed(registry: &MyIPRegistry, license_id: address, ctx: &TxContext): bool {
        registry_has_permission(registry, license_id, PERMISSION_ALLOW_REACTIONS, ctx)
    }
    
    /// Check if reposting is allowed (registry version)
    public fun registry_is_reposting_allowed(registry: &MyIPRegistry, license_id: address, ctx: &TxContext): bool {
        registry_has_permission(registry, license_id, PERMISSION_ALLOW_REPOSTS, ctx)
    }
    
    /// Check if quote posting is allowed (registry version)
    public fun registry_is_quoting_allowed(registry: &MyIPRegistry, license_id: address, ctx: &TxContext): bool {
        registry_has_permission(registry, license_id, PERMISSION_ALLOW_QUOTES, ctx)
    }
    
    /// Check if tipping is allowed (registry version)
    public fun registry_is_tipping_allowed(registry: &MyIPRegistry, license_id: address, ctx: &TxContext): bool {
        registry_has_permission(registry, license_id, PERMISSION_ALLOW_TIPS, ctx)
    }
    
    /// Check if commercial use is allowed (registry version)
    public fun registry_is_commercial_use_allowed(registry: &MyIPRegistry, license_id: address, ctx: &TxContext): bool {
        registry_has_permission(registry, license_id, PERMISSION_COMMERCIAL_USE, ctx)
    }
    
    /// Check if derivatives are allowed (registry version)
    public fun registry_is_derivatives_allowed(registry: &MyIPRegistry, license_id: address, ctx: &TxContext): bool {
        registry_has_permission(registry, license_id, PERMISSION_DERIVATIVES_ALLOWED, ctx)
    }
    
    /// Check if it's a public license (registry version)
    public fun registry_is_public_license(registry: &MyIPRegistry, license_id: address, ctx: &TxContext): bool {
        registry_has_permission(registry, license_id, PERMISSION_PUBLIC_LICENSE, ctx)
    }
    
    /// Check if revenue is redirected (registry version)
    public fun registry_is_revenue_redirected(registry: &MyIPRegistry, license_id: address, ctx: &TxContext): bool {
        registry_has_permission(registry, license_id, PERMISSION_REVENUE_REDIRECT, ctx)
    }
    
    /// Get revenue recipient from registry
    public fun registry_get_revenue_recipient(registry: &MyIPRegistry, license_id: address): address {
        assert!(table::contains(&registry.revenue_recipients, license_id), ELicenseNotRegistered);
        *table::borrow(&registry.revenue_recipients, license_id)
    }
    
    /// Get creator from registry
    public fun registry_get_creator(registry: &MyIPRegistry, license_id: address): address {
        assert!(table::contains(&registry.creators, license_id), ELicenseNotRegistered);
        *table::borrow(&registry.creators, license_id)
    }
    
    // === Social Interaction Permission Checks for Posts ===
    
    /// Check if commenting is allowed
    public fun is_commenting_allowed(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_ALLOW_COMMENTS) != 0
    }
    
    /// Check if reactions/likes are allowed
    public fun is_reactions_allowed(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_ALLOW_REACTIONS) != 0
    }
    
    /// Check if reposting is allowed
    public fun is_reposting_allowed(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_ALLOW_REPOSTS) != 0
    }
    
    /// Check if quote posting is allowed
    public fun is_quoting_allowed(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_ALLOW_QUOTES) != 0
    }
    
    /// Check if tipping is allowed
    public fun is_tipping_allowed(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_ALLOW_TIPS) != 0
    }
    
    // === Validation Functions ===
    
    /// Check if commercial use is allowed
    public fun is_commercial_use_allowed(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_COMMERCIAL_USE) != 0
    }
    
    /// Check if derivatives are allowed
    public fun is_derivatives_allowed(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_DERIVATIVES_ALLOWED) != 0
    }
    
    /// Check if it's a public license
    public fun is_public_license(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_PUBLIC_LICENSE) != 0
    }
    
    /// Check if authority is required
    public fun is_authority_required(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_AUTHORITY_REQUIRED) != 0
    }
    
    /// Check if share-alike is required
    public fun is_share_alike_required(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_SHARE_ALIKE) != 0
    }
    
    /// Check if attribution is required
    public fun is_attribution_required(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_REQUIRE_ATTRIBUTION) != 0
    }
    
    /// Check if revenue is redirected
    public fun is_revenue_redirected(license: &MyIP): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & PERMISSION_REVENUE_REDIRECT) != 0
    }
    
    /// Check if a specific permission is granted
    public fun has_permission(license: &MyIP, permission: u64): bool {
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        (license.permission_flags & permission) != 0
    }
    
    /// Check if license has expired
    public fun is_expired(license: &MyIP, current_epoch: u64): bool {
        if (option::is_some(&license.expires_at)) {
            let expires_at = option::borrow(&license.expires_at);
            return current_epoch >= *expires_at
        };
        false
    }
    
    /// Validate license for a specific operation
    public fun validate_license_for_operation(
        license: &MyIP,
        required_permission: u64,
        current_epoch: u64
    ): bool {
        // Check license state
        if (license.license_state != LICENSE_STATE_ACTIVE) {
            return false
        };
        
        // Check expiration
        if (is_expired(license, current_epoch)) {
            return false
        };
        
        // Check permission
        has_permission(license, required_permission)
    }
    
    // === Getter Functions ===
    
    /// Get creator of the IP
    public fun creator(ip: &MyIP): address {
        ip.creator
    }
    
    /// Get name of the IP
    public fun name(ip: &MyIP): String {
        ip.name
    }
    
    /// Get description of the IP
    public fun description(ip: &MyIP): String {
        ip.description
    }
    
    /// Get creation time of the IP
    public fun creation_time(ip: &MyIP): u64 {
        ip.creation_time
    }
    
    /// Get license type
    public fun license_type(ip: &MyIP): u8 {
        ip.license_type
    }
    
    /// Get permission flags
    public fun permission_flags(ip: &MyIP): u64 {
        ip.permission_flags
    }
    
    /// Get license state
    public fun license_state(ip: &MyIP): u8 {
        ip.license_state
    }
    
    /// Get proof of creativity ID
    public fun proof_of_creativity_id(ip: &MyIP): &Option<address> {
        &ip.proof_of_creativity_id
    }
    
    /// Get custom license URI
    public fun custom_license_uri(ip: &MyIP): &Option<Url> {
        &ip.custom_license_uri
    }
    
    /// Get revenue recipient
    public fun revenue_recipient(ip: &MyIP): &Option<address> {
        &ip.revenue_recipient
    }
    
    /// Is license transferable
    public fun is_transferable(ip: &MyIP): bool {
        ip.transferable
    }
    
    /// Get expiration time
    public fun expires_at(ip: &MyIP): &Option<u64> {
        &ip.expires_at
    }
    
    /// Get the ID of the MyIP
    public fun id(ip: &MyIP): &UID {
        &ip.id
    }
    
    /// Get the address of the MyIP
    public fun id_address(ip: &MyIP): address {
        object::uid_to_address(&ip.id)
    }
    
    // === License Template Helpers ===
    
    /// Create a Creative Commons Zero license (CC0 - public domain)
    public fun cc0_license_flags(): u64 {
        PERMISSION_COMMERCIAL_USE | 
        PERMISSION_DERIVATIVES_ALLOWED | 
        PERMISSION_PUBLIC_LICENSE |
        PERMISSION_ALLOW_COMMENTS |
        PERMISSION_ALLOW_REACTIONS |
        PERMISSION_ALLOW_REPOSTS |
        PERMISSION_ALLOW_QUOTES |
        PERMISSION_ALLOW_TIPS
    }
    
    /// Create a Creative Commons BY license (Attribution)
    public fun cc_by_license_flags(): u64 {
        PERMISSION_COMMERCIAL_USE | 
        PERMISSION_DERIVATIVES_ALLOWED | 
        PERMISSION_PUBLIC_LICENSE | 
        PERMISSION_REQUIRE_ATTRIBUTION |
        PERMISSION_ALLOW_COMMENTS |
        PERMISSION_ALLOW_REACTIONS |
        PERMISSION_ALLOW_REPOSTS |
        PERMISSION_ALLOW_QUOTES |
        PERMISSION_ALLOW_TIPS
    }
    
    /// Create a Creative Commons BY-SA license (Attribution-ShareAlike)
    public fun cc_by_sa_license_flags(): u64 {
        PERMISSION_COMMERCIAL_USE | 
        PERMISSION_DERIVATIVES_ALLOWED | 
        PERMISSION_PUBLIC_LICENSE | 
        PERMISSION_REQUIRE_ATTRIBUTION |
        PERMISSION_SHARE_ALIKE |
        PERMISSION_ALLOW_COMMENTS |
        PERMISSION_ALLOW_REACTIONS |
        PERMISSION_ALLOW_REPOSTS |
        PERMISSION_ALLOW_QUOTES |
        PERMISSION_ALLOW_TIPS
    }
    
    /// Create a Creative Commons BY-NC license (Attribution-NonCommercial)
    public fun cc_by_nc_license_flags(): u64 {
        PERMISSION_DERIVATIVES_ALLOWED | 
        PERMISSION_PUBLIC_LICENSE | 
        PERMISSION_REQUIRE_ATTRIBUTION |
        PERMISSION_ALLOW_COMMENTS |
        PERMISSION_ALLOW_REACTIONS |
        PERMISSION_ALLOW_REPOSTS |
        PERMISSION_ALLOW_QUOTES |
        PERMISSION_ALLOW_TIPS
        // Note: No COMMERCIAL_USE flag
    }
    
    /// Create a Creative Commons BY-NC-SA license (Attribution-NonCommercial-ShareAlike)
    public fun cc_by_nc_sa_license_flags(): u64 {
        PERMISSION_DERIVATIVES_ALLOWED | 
        PERMISSION_PUBLIC_LICENSE | 
        PERMISSION_REQUIRE_ATTRIBUTION |
        PERMISSION_SHARE_ALIKE |
        PERMISSION_ALLOW_COMMENTS |
        PERMISSION_ALLOW_REACTIONS |
        PERMISSION_ALLOW_REPOSTS |
        PERMISSION_ALLOW_QUOTES |
        PERMISSION_ALLOW_TIPS
        // Note: No COMMERCIAL_USE flag
    }
    
    /// Create a Creative Commons BY-ND license (Attribution-NoDerivatives)
    public fun cc_by_nd_license_flags(): u64 {
        PERMISSION_COMMERCIAL_USE | 
        PERMISSION_PUBLIC_LICENSE | 
        PERMISSION_REQUIRE_ATTRIBUTION |
        PERMISSION_ALLOW_COMMENTS |
        PERMISSION_ALLOW_REACTIONS |
        PERMISSION_ALLOW_TIPS
        // Note: No DERIVATIVES_ALLOWED, ALLOW_REPOSTS, ALLOW_QUOTES flags
    }
    
    /// Create a personal use only license
    public fun personal_use_license_flags(): u64 {
        PERMISSION_PUBLIC_LICENSE |
        PERMISSION_REQUIRE_ATTRIBUTION |
        PERMISSION_ALLOW_COMMENTS |
        PERMISSION_ALLOW_REACTIONS
        // Note: No COMMERCIAL_USE, DERIVATIVES_ALLOWED, ALLOW_REPOSTS, ALLOW_QUOTES, ALLOW_TIPS flags
    }
    
    /// Create a token bound license
    public fun token_bound_license_flags(): u64 {
        PERMISSION_COMMERCIAL_USE |
        PERMISSION_AUTHORITY_REQUIRED |
        PERMISSION_REQUIRE_ATTRIBUTION |
        PERMISSION_ALLOW_COMMENTS |
        PERMISSION_ALLOW_REACTIONS |
        PERMISSION_ALLOW_REPOSTS |
        PERMISSION_ALLOW_QUOTES |
        PERMISSION_ALLOW_TIPS
    }
    
    /// Create a private license (view only)
    public fun private_license_flags(): u64 {
        PERMISSION_REQUIRE_ATTRIBUTION |
        PERMISSION_ALLOW_REACTIONS
        // No other permissions allowed
    }
    
    /// Add revenue redirection to a license
    public fun add_revenue_redirection(base_flags: u64): u64 {
        base_flags | PERMISSION_REVENUE_REDIRECT
    }
    
    /// === Versioning Functions ===
    
    /// Get the version of a MyIP
    public fun version(ip: &MyIP): u64 {
        ip.version
    }
    
    /// Get a mutable reference to the MyIP version (for upgrade module)
    public fun borrow_version_mut(ip: &mut MyIP): &mut u64 {
        &mut ip.version
    }
    
    /// Get the version of the registry
    public fun registry_version(registry: &MyIPRegistry): u64 {
        registry.version
    }
    
    /// Get a mutable reference to the registry version
    public fun borrow_registry_version_mut(registry: &mut MyIPRegistry): &mut u64 {
        &mut registry.version
    }
    
    /// Migration function for MyIP
    public entry fun migrate_my_ip(
        my_ip: &mut MyIP,
        _: &AdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        
        // Verify this is an upgrade (new version > current version)
        assert!(my_ip.version < current_version, EWrongVersion);
        
        // Remember old version and update to new version
        let old_version = my_ip.version;
        my_ip.version = current_version;
        
        // Emit event for object migration
        let my_ip_id = object::id(my_ip);
        upgrade::emit_migration_event(
            my_ip_id,
            string::utf8(b"MyIP"),
            old_version,
            tx_context::sender(ctx)
        );
        
        // Any migration logic can be added here for future upgrades
    }
    
    /// Migration function for MyIPRegistry
    public entry fun migrate_registry(
        registry: &mut MyIPRegistry,
        _: &AdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        
        // Verify this is an upgrade (new version > current version)
        assert!(registry.version < current_version, EWrongVersion);
        
        // Remember old version and update to new version
        let old_version = registry.version;
        registry.version = current_version;
        
        // Emit event for object migration
        let registry_id = object::id(registry);
        upgrade::emit_migration_event(
            registry_id,
            string::utf8(b"MyIPRegistry"),
            old_version,
            tx_context::sender(ctx)
        );
        
        // Any migration logic can be added here for future upgrades
    }

    // === Test Only Functions ===

    #[test_only]
    /// Initialize registry for testing
    public fun test_init(ctx: &mut TxContext) {
        // Create and share the registry
        let registry = MyIPRegistry {
            id: object::new(ctx),
            permissions: table::new(ctx),
            license_types: table::new(ctx),
            revenue_recipients: table::new(ctx),
            states: table::new(ctx),
            creators: table::new(ctx),
            expirations: table::new(ctx),
            version: 0, // Use 0 for testing
        };
        
        // Share the registry
        transfer::share_object(registry);
    }
}