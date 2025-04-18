// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// A module for handling encrypted content on MySocial platform
/// Provides cryptographically secure methods for storing, accessing,
/// and sharing encrypted content with payment-based access control.

module social_contracts::encrypted_content {
    use std::string::{Self, String};
    
    use mys::dynamic_field;
    use mys::event;
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::mys::MYS;
    
    use social_contracts::profile::{Self, Profile};

    // ====== Error codes ======
    const EUnauthorized: u64 = 1;
    const EInsufficientPayment: u64 = 3;
    const EAccessKeyNotFound: u64 = 6;
    const EInvalidEncryptionScheme: u64 = 8;
    const ETierNotFound: u64 = 10;

    // ====== Constants ======
    // Signature scheme flags (matches Sui standards)
    const SIG_FLAG_ED25519: u8 = 0x00;
    const SIG_FLAG_SECP256K1: u8 = 0x01;
    const SIG_FLAG_SECP256R1: u8 = 0x02;
    
    // Content types (only using CONTENT_TYPE_PROFILE in this file)
    const CONTENT_TYPE_PROFILE: u8 = 2;
    
    // Access status
    const ACCESS_STATUS_ACTIVE: u8 = 1;
    const ACCESS_STATUS_REVOKED: u8 = 2;

    // Field names for dynamic fields
    const ACCESS_KEYS_FIELD: vector<u8> = b"access_keys";
    const CONTENT_METADATA_FIELD: vector<u8> = b"content_metadata";
    const TIERS_FIELD: vector<u8> = b"tiers";

    // ====== Core data structures ======

    /// Primary struct representing encrypted content
    public struct EncryptedContent has key, store {
        id: UID,
        /// Owner of the content
        owner: address,
        /// Type of content (post, profile, message, etc.)
        content_type: u8,
        /// Encrypted content data
        encrypted_data: vector<u8>,
        /// Content encryption scheme identifier
        encryption_scheme: u8,
        /// Public metadata visible to everyone
        public_metadata: String,
        /// Hash of the original content (for integrity verification)
        content_hash: vector<u8>,
        /// Creation timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
        /// Platform fee in basis points (e.g., 250 = 2.5%)
        platform_fee_bps: u64,
        /// List of tier IDs for tracking
        tier_ids: vector<String>,
    }

    /// Payment tier with different access levels and pricing
    public struct PaymentTier has store, copy, drop {
        /// Tier identifier
        tier_id: String,
        /// Price in MYS tokens
        price: u64,
        /// Human-readable name for this tier
        name: String,
        /// Description of what this tier provides
        description: String,
        /// Duration of access in epochs (0 for permanent)
        duration_epochs: u64,
        /// Encrypted tier key (encrypted with owner's public key)
        encrypted_tier_key: vector<u8>,
        /// Public key used for content encryption in this tier
        tier_public_key: vector<u8>,
        /// Hash of the tier key for verification
        tier_key_hash: vector<u8>,
    }

    /// Information about granted access to content
    public struct AccessGrant has store, copy, drop {
        /// Address that has access
        recipient: address,
        /// Encrypted access key for this recipient
        encrypted_access_key: vector<u8>,
        /// Timestamp when access was granted
        granted_at: u64,
        /// Expiration timestamp (0 for never)
        expires_at: u64,
        /// Tier ID this access belongs to
        tier_id: String,
        /// Payment amount
        payment_amount: u64,
        /// Current status of this access
        status: u8,
        /// Cryptographic nonce used for this specific access grant
        nonce: vector<u8>,
    }

    /// Content metadata (partially encrypted)
    public struct ContentMetadata has store, copy, drop {
        /// Public title/name
        title: String,
        /// Public description/preview
        description: String,
        /// Public tags
        tags: vector<String>,
        /// Additional public attributes (serialized as JSON)
        public_attributes: String,
        /// Hash of encrypted attributes 
        encrypted_attributes_hash: vector<u8>,
    }

    // ====== Events ======

    /// Event emitted when encrypted content is created
    public struct ContentCreatedEvent has copy, drop {
        content_id: address,
        owner: address,
        content_type: u8,
        content_hash: vector<u8>,
        created_at: u64,
    }

    /// Event emitted when access is granted to content
    public struct AccessGrantedEvent has copy, drop {
        content_id: address,
        recipient: address,
        tier_id: String,
        payment_amount: u64,
        granted_at: u64,
        expires_at: u64,
    }

    /// Event emitted when access is revoked
    public struct AccessRevokedEvent has copy, drop {
        content_id: address,
        recipient: address,
        revoked_by: address,
        revoked_at: u64,
    }

    /// Event emitted when content is updated
    public struct ContentUpdatedEvent has copy, drop {
        content_id: address,
        owner: address,
        content_hash: vector<u8>,
        updated_at: u64,
    }

    /// Event emitted when a payment tier is created
    public struct TierCreatedEvent has copy, drop {
        content_id: address,
        tier_id: String,
        price: u64,
        name: String,
        created_at: u64,
    }

    // ====== Core functions ======

    /// Create new encrypted content
    public entry fun create_encrypted_content(
        profile: &Profile,
        encrypted_data: vector<u8>,
        content_type: u8,
        encryption_scheme: u8,
        public_metadata: String,
        content_hash: vector<u8>,
        platform_fee_bps: u64,
        ctx: &mut TxContext
    ) {
        // Verify sender is the profile owner
        let sender = tx_context::sender(ctx);
        assert!(profile::owner(profile) == sender, EUnauthorized);
        
        // Validate encryption scheme
        assert!(
            encryption_scheme == SIG_FLAG_ED25519 || 
            encryption_scheme == SIG_FLAG_SECP256K1 || 
            encryption_scheme == SIG_FLAG_SECP256R1, 
            EInvalidEncryptionScheme
        );
        
        let now = tx_context::epoch(ctx);
        
        // Create content object
        let mut content = EncryptedContent {
            id: object::new(ctx),
            owner: sender,
            content_type,
            encrypted_data,
            encryption_scheme,
            public_metadata,
            content_hash,
            created_at: now,
            updated_at: now,
            platform_fee_bps,
            tier_ids: vector::empty(),
        };
        
        // Initialize access keys table as a dynamic field
        let access_keys = table::new<address, AccessGrant>(ctx);
        dynamic_field::add(&mut content.id, ACCESS_KEYS_FIELD, access_keys);
        
        // Initialize tiers table
        let tiers = table::new<String, PaymentTier>(ctx);
        dynamic_field::add(&mut content.id, TIERS_FIELD, tiers);
        
        // Initialize content metadata
        let metadata = ContentMetadata {
            title: string::utf8(b""),
            description: string::utf8(b""),
            tags: vector::empty(),
            public_attributes: string::utf8(b"{}"),
            encrypted_attributes_hash: vector::empty(),
        };
        dynamic_field::add(&mut content.id, CONTENT_METADATA_FIELD, metadata);
        
        let content_id = object::uid_to_address(&content.id);
        
        // If this is profile content, link it to the profile
        if (content_type == CONTENT_TYPE_PROFILE) {
            link_to_profile(profile, content_id, ctx);
        };
        
        // Emit content creation event
        event::emit(ContentCreatedEvent {
            content_id,
            owner: sender,
            content_type,
            content_hash,
            created_at: now,
        });
        
        // Transfer content object to owner
        transfer::transfer(content, sender);
    }

    /// Create a new payment tier for content
    public entry fun create_payment_tier(
        content: &mut EncryptedContent,
        tier_id: String,
        price: u64,
        name: String,
        description: String,
        duration_epochs: u64,
        encrypted_tier_key: vector<u8>,
        tier_public_key: vector<u8>,
        tier_key_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        // Verify sender is the content owner
        let sender = tx_context::sender(ctx);
        assert!(content.owner == sender, EUnauthorized);
        
        let now = tx_context::epoch(ctx);
        
        // Create new payment tier
        let tier = PaymentTier {
            tier_id,
            price,
            name,
            description,
            duration_epochs,
            encrypted_tier_key,
            tier_public_key,
            tier_key_hash,
        };
        
        // Add tier to the tiers table
        let tiers = dynamic_field::borrow_mut<vector<u8>, Table<String, PaymentTier>>(&mut content.id, TIERS_FIELD);
        assert!(!table::contains(tiers, tier_id), ETierNotFound); // Tier ID must be unique
        table::add(tiers, tier_id, tier);
        
        // Add tier_id to the content's tier_ids list for tracking
        vector::push_back(&mut content.tier_ids, tier_id);
        
        // Emit tier creation event
        event::emit(TierCreatedEvent {
            content_id: object::uid_to_address(&content.id),
            tier_id,
            price,
            name,
            created_at: now,
        });
    }

    /// Pay to unlock encrypted content
    public entry fun unlock_content_with_payment(
        content: &mut EncryptedContent,
        payment: &mut Coin<MYS>,
        tier_id: String,
        recipient_public_key: vector<u8>,
        nonce: vector<u8>,
        platform_treasury: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let now = tx_context::epoch(ctx);
        let content_id = object::uid_to_address(&content.id);
        let content_owner = content.owner;
        
        // Get the tiers table
        let tiers = dynamic_field::borrow<vector<u8>, Table<String, PaymentTier>>(&content.id, TIERS_FIELD);
        
        // Verify tier exists
        assert!(table::contains(tiers, tier_id), ETierNotFound);
        
        // Get the payment tier
        let tier = table::borrow(tiers, tier_id);
        
        // Verify sufficient payment
        let price = tier.price;
        assert!(coin::value(payment) >= price, EInsufficientPayment);
        
        // Split the payment
        let mut paid_coin = coin::split(payment, price, ctx);
        
        // Calculate platform fee
        let platform_fee = (price * content.platform_fee_bps) / 10000;
        
        // If platform fee is non-zero, split it off
        if (platform_fee > 0) {
            // Split off platform fee and send to platform treasury
            let platform_fee_coin = coin::split(&mut paid_coin, platform_fee, ctx);
            transfer::public_transfer(platform_fee_coin, platform_treasury);
        };
        
        // Send remaining payment directly to content owner
        transfer::public_transfer(paid_coin, content_owner);
        
        // Generate access key using recipient's public key and tier key
        let encrypted_access_key = client_encrypt_access_key(
            tier.encrypted_tier_key,
            tier.tier_public_key,
            recipient_public_key, 
            nonce, 
            content.encryption_scheme
        );
        
        // Calculate expiration time if applicable
        let expires_at = if (tier.duration_epochs == 0) {
            0 // Never expires
        } else {
            now + tier.duration_epochs
        };
        
        // Create access grant
        let access_grant = AccessGrant {
            recipient: sender,
            encrypted_access_key,
            granted_at: now,
            expires_at,
            tier_id,
            payment_amount: price,
            status: ACCESS_STATUS_ACTIVE,
            nonce,
        };
        
        // Get the access keys table
        let access_keys = dynamic_field::borrow_mut<vector<u8>, Table<address, AccessGrant>>(&mut content.id, ACCESS_KEYS_FIELD);
        
        // Add or update access for the sender
        if (table::contains(access_keys, sender)) {
            // Update existing access
            *table::borrow_mut(access_keys, sender) = access_grant;
        } else {
            // Add new access
            table::add(access_keys, sender, access_grant);
        };
        
        // Emit access granted event
        event::emit(AccessGrantedEvent {
            content_id,
            recipient: sender,
            tier_id,
            payment_amount: price,
            granted_at: now,
            expires_at,
        });
    }

    /// Grant free access to content (owner only)
    public entry fun grant_free_access(
        content: &mut EncryptedContent,
        recipient: address,
        tier_id: String,
        recipient_public_key: vector<u8>,
        nonce: vector<u8>,
        duration_epochs: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(content.owner == sender, EUnauthorized);
        
        let now = tx_context::epoch(ctx);
        let content_id = object::uid_to_address(&content.id);
        
        // Get the tiers table
        let tiers = dynamic_field::borrow<vector<u8>, Table<String, PaymentTier>>(&content.id, TIERS_FIELD);
        
        // Verify tier exists
        assert!(table::contains(tiers, tier_id), ETierNotFound);
        
        // Get the payment tier
        let tier = table::borrow(tiers, tier_id);
        
        // Generate access key using recipient's public key and tier key
        let encrypted_access_key = client_encrypt_access_key(
            tier.encrypted_tier_key,
            tier.tier_public_key,
            recipient_public_key, 
            nonce, 
            content.encryption_scheme
        );
        
        // Calculate expiration time if applicable
        let expires_at = if (duration_epochs == 0) {
            0 // Never expires
        } else {
            now + duration_epochs
        };
        
        // Create access grant with zero payment
        let access_grant = AccessGrant {
            recipient,
            encrypted_access_key,
            granted_at: now,
            expires_at,
            tier_id,
            payment_amount: 0, // Free access
            status: ACCESS_STATUS_ACTIVE,
            nonce,
        };
        
        // Get the access keys table
        let access_keys = dynamic_field::borrow_mut<vector<u8>, Table<address, AccessGrant>>(&mut content.id, ACCESS_KEYS_FIELD);
        
        // Add or update access for the recipient
        if (table::contains(access_keys, recipient)) {
            // Update existing access
            *table::borrow_mut(access_keys, recipient) = access_grant;
        } else {
            // Add new access
            table::add(access_keys, recipient, access_grant);
        };
        
        // Emit access granted event
        event::emit(AccessGrantedEvent {
            content_id,
            recipient,
            tier_id,
            payment_amount: 0, // Free access
            granted_at: now,
            expires_at,
        });
    }

    /// Revoke access to content (owner only)
    public entry fun revoke_access(
        content: &mut EncryptedContent,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(content.owner == sender, EUnauthorized);
        
        let now = tx_context::epoch(ctx);
        
        // Get the access keys table
        let access_keys = dynamic_field::borrow_mut<vector<u8>, Table<address, AccessGrant>>(&mut content.id, ACCESS_KEYS_FIELD);
        
        // Verify recipient has access
        assert!(table::contains(access_keys, recipient), EAccessKeyNotFound);
        
        // Mark access as revoked
        let access_grant = table::borrow_mut(access_keys, recipient);
        access_grant.status = ACCESS_STATUS_REVOKED;
        
        // Emit access revoked event
        event::emit(AccessRevokedEvent {
            content_id: object::uid_to_address(&content.id),
            recipient,
            revoked_by: sender,
            revoked_at: now,
        });
    }

    /// Update encrypted content (owner only)
    public entry fun update_content(
        content: &mut EncryptedContent,
        new_encrypted_data: vector<u8>,
        new_content_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(content.owner == sender, EUnauthorized);
        
        let now = tx_context::epoch(ctx);
        
        // Update content
        content.encrypted_data = new_encrypted_data;
        content.content_hash = new_content_hash;
        content.updated_at = now;
        
        // Emit content updated event
        event::emit(ContentUpdatedEvent {
            content_id: object::uid_to_address(&content.id),
            owner: sender,
            content_hash: new_content_hash,
            updated_at: now,
        });
    }

    /// Update content metadata
    public entry fun update_content_metadata(
        content: &mut EncryptedContent,
        title: String,
        description: String,
        tags: vector<String>,
        public_attributes: String,
        encrypted_attributes_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(content.owner == sender, EUnauthorized);
        
        // Get and update the metadata
        let metadata = dynamic_field::borrow_mut<vector<u8>, ContentMetadata>(&mut content.id, CONTENT_METADATA_FIELD);
        
        metadata.title = title;
        metadata.description = description;
        metadata.tags = tags;
        metadata.public_attributes = public_attributes;
        metadata.encrypted_attributes_hash = encrypted_attributes_hash;
        
        // Update the content's last updated timestamp
        content.updated_at = tx_context::epoch(ctx);
    }

    // ====== Helper functions ======

    /// Link encrypted content to a profile
    fun link_to_profile(
        profile: &Profile,
        _content_id: address,
        _ctx: &mut TxContext
    ) {
        // Since we can't modify profile directly through profile::id(profile),
        // this function would need to be implemented differently.
        // For now, we'll leave it as a placeholder.
        
        // In a real implementation, we would need to:
        // 1. Have a separate mapping of profiles to their content
        // 2. Or add a function to the profile module to link content
        
        // Get profile ID for logging purposes only
        let _profile_id = profile::get_id_address(profile);
    }

    /// Verify access to encrypted content
    fun verify_access(
        content: &EncryptedContent,
        user: address,
        ctx: &TxContext
    ): bool {
        // Get the access keys table
        if (!dynamic_field::exists_(&content.id, ACCESS_KEYS_FIELD)) {
            return false
        };
        
        let access_keys = dynamic_field::borrow<vector<u8>, Table<address, AccessGrant>>(&content.id, ACCESS_KEYS_FIELD);
        
        // Check if user has access
        if (!table::contains(access_keys, user)) {
            return false
        };
        
        // Get the access grant
        let access = table::borrow(access_keys, user);
        
        // Check if access is active
        if (access.status != ACCESS_STATUS_ACTIVE) {
            return false
        };
        
        // Check if access has expired
        let now = tx_context::epoch(ctx);
        if (access.expires_at != 0 && now > access.expires_at) {
            return false
        };
        
        true
    }

    /// Client proxy function for access key generation
    /// NOTE: In production, this is a placeholder where clients would provide their own encrypted keys.
    /// This function should be replaced with one that accepts a client-encrypted access key.
    public fun client_encrypt_access_key(
        _encrypted_tier_key: vector<u8>,
        _tier_public_key: vector<u8>,
        _recipient_public_key: vector<u8>,
        nonce: vector<u8>,
        _encryption_scheme: u8
    ): vector<u8> {
        // In production, the client should encrypt access keys and provide them directly
        // This is a temporary placeholder that returns the nonce as a mock "encrypted" key
        // IMPORTANT: Replace this with actual client-provided encrypted keys in production!
        nonce
    }

    // ====== Public accessor functions ======

    /// Get the encrypted data if user has access
    public fun get_encrypted_data(
        content: &EncryptedContent,
        ctx: &TxContext
    ): vector<u8> {
        let sender = tx_context::sender(ctx);
        
        // If sender is the owner, they always have access
        if (content.owner == sender) {
            return content.encrypted_data
        };
        
        // Otherwise, verify access
        assert!(verify_access(content, sender, ctx), EUnauthorized);
        
        content.encrypted_data
    }

    /// Get the encrypted access key for a user
    public fun get_access_key(
        content: &EncryptedContent,
        ctx: &TxContext
    ): Option<vector<u8>> {
        let sender = tx_context::sender(ctx);
        
        // If user has no access, return none
        if (!dynamic_field::exists_(&content.id, ACCESS_KEYS_FIELD)) {
            return option::none()
        };
        
        let access_keys = dynamic_field::borrow<vector<u8>, Table<address, AccessGrant>>(&content.id, ACCESS_KEYS_FIELD);
        
        if (!table::contains(access_keys, sender)) {
            return option::none()
        };
        
        let access = table::borrow(access_keys, sender);
        
        // Check if access is active and not expired
        let now = tx_context::epoch(ctx);
        if (access.status != ACCESS_STATUS_ACTIVE || (access.expires_at != 0 && now > access.expires_at)) {
            return option::none()
        };
        
        option::some(access.encrypted_access_key)
    }

    /// Check if a user has access to content
    public fun has_access(
        content: &EncryptedContent,
        user: address,
        ctx: &TxContext
    ): bool {
        // If user is the owner, they always have access
        if (content.owner == user) {
            return true
        };
        
        verify_access(content, user, ctx)
    }

    /// Get the owner of the content
    public fun owner(content: &EncryptedContent): address {
        content.owner
    }

    /// Get the content type
    public fun content_type(content: &EncryptedContent): u8 {
        content.content_type
    }

    /// Get the content hash for verification
    public fun content_hash(content: &EncryptedContent): vector<u8> {
        content.content_hash
    }

    /// Get the public metadata
    public fun public_metadata(content: &EncryptedContent): String {
        content.public_metadata
    }

    /// Get content creation timestamp
    public fun created_at(content: &EncryptedContent): u64 {
        content.created_at
    }

    /// Get content last updated timestamp
    public fun updated_at(content: &EncryptedContent): u64 {
        content.updated_at
    }

    /// Get detailed content metadata
    public fun get_content_metadata(content: &EncryptedContent): ContentMetadata {
        *dynamic_field::borrow<vector<u8>, ContentMetadata>(&content.id, CONTENT_METADATA_FIELD)
    }

    /// Get a tier's details
    public fun get_tier_details(
        content: &EncryptedContent,
        tier_id: String
    ): Option<PaymentTier> {
        if (!dynamic_field::exists_(&content.id, TIERS_FIELD)) {
            return option::none()
        };
        
        let tiers = dynamic_field::borrow<vector<u8>, Table<String, PaymentTier>>(&content.id, TIERS_FIELD);
        
        if (!table::contains(tiers, tier_id)) {
            return option::none()
        };
        
        option::some(*table::borrow(tiers, tier_id))
    }

    /// Get all tier IDs for a piece of content
    public fun get_tier_ids(content: &EncryptedContent): vector<String> {
        // Return the tracked tier IDs
        content.tier_ids
    }

    /// Get the platform fee in basis points
    public fun platform_fee_bps(content: &EncryptedContent): u64 {
        content.platform_fee_bps
    }

    // ====== Testing functions ======
    #[test_only]
    /// Create empty content for testing
    public fun create_test_content(ctx: &mut TxContext): EncryptedContent {
        let id = object::new(ctx);
        let mut content = EncryptedContent {
            id,
            owner: tx_context::sender(ctx),
            content_type: CONTENT_TYPE_PROFILE,
            encrypted_data: b"test",
            encryption_scheme: SIG_FLAG_ED25519,
            public_metadata: string::utf8(b"Test Content"),
            content_hash: b"hash",
            created_at: tx_context::epoch(ctx),
            updated_at: tx_context::epoch(ctx),
            platform_fee_bps: 250, // 2.5% fee
            tier_ids: vector::empty(),
        };
        
        let access_keys = table::new<address, AccessGrant>(ctx);
        dynamic_field::add(&mut content.id, ACCESS_KEYS_FIELD, access_keys);
        
        let tiers = table::new<String, PaymentTier>(ctx);
        dynamic_field::add(&mut content.id, TIERS_FIELD, tiers);
        
        let metadata = ContentMetadata {
            title: string::utf8(b"Test Title"),
            description: string::utf8(b"Test Description"),
            tags: vector::empty(),
            public_attributes: string::utf8(b"{}"),
            encrypted_attributes_hash: vector::empty(),
        };
        dynamic_field::add(&mut content.id, CONTENT_METADATA_FIELD, metadata);
        
        content
    }
} 