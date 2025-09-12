// Copyright (c) The Social Proof Foundation, LLC.
// SPDX-License-Identifier: Apache-2.0

/// Universal MyIP module for encrypted data monetization
/// Supports both one-time purchases and subscription access
/// Can be attached to posts (gated content) or profiles (data monetization)

#[allow(duplicate_alias, unused_use, unused_const)]
module social_contracts::my_ip {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    
    use mys::{
        object::{Self, UID, ID},
        tx_context::{Self, TxContext},
        transfer,
        table::{Self, Table},
        coin::{Self, Coin},
        balance::{Self, Balance},
        clock::{Self, Clock},
        event
    };
    use mys::mys::MYS;
    
    // Proper Seal encryption support
    use seal::bf_hmac_encryption::{Self, EncryptedObject, VerifiedDerivedKey, PublicKey};
    
    use social_contracts::upgrade::{Self, UpgradeAdminCap};

    // === Error codes ===
    const EUnauthorized: u64 = 1;
    const ENotForSale: u64 = 2;
    const EPriceMismatch: u64 = 3;
    const ESelfPurchase: u64 = 4;
    const EAlreadyPurchased: u64 = 5;
    const EActiveSubscription: u64 = 6;
    const EInvalidInput: u64 = 7;
    const ESubscriptionExpired: u64 = 8;
    const EOverflow: u64 = 9;
    const EInvalidTimeRange: u64 = 10;

    // === Constants ===
    const MAX_TAGS: u64 = 10;
    const MAX_SUBSCRIPTION_DAYS: u64 = 365;
    const MILLISECONDS_PER_DAY: u64 = 86_400_000;
    const MAX_FREE_ACCESS_GRANTS: u64 = 100_000; // Limit free access to 100k users
    const MAX_U64: u64 = 18446744073709551615; // Max u64 value for overflow protection

    /// Universal MyIP for encrypted data monetization using proper Seal patterns
    public struct MyIP has key, store {
        id: UID,
        owner: address,
        
        /// Content metadata (title and description removed)
        media_type: String,                     // "text", "audio", "image", "gif", "video", "article", "data", "statistics"
        tags: vector<String>,                   // Searchable tags
        platform_id: Option<address>,          // Optional platform identification
        
        /// Time and context
        timestamp_start: u64,
        timestamp_end: Option<u64>,             // For time-range data or updates
        created_at: u64,
        last_updated: u64,
        
        /// Properly sealed content using Seal encryption
        encrypted_data: vector<u8>,             // Raw encrypted data from Seal
        encryption_id: vector<u8>,              // Seal encryption ID for decryption
        
        /// Pricing options - user controlled
        one_time_price: Option<u64>,            // Price for one-time access (0 = free)
        subscription_price: Option<u64>,        // Price for subscription access
        subscription_duration_days: u64,       // Subscription duration in days
        
        /// Access tracking
        purchasers: Table<address, bool>,       // One-time purchase access
        subscribers: Table<address, u64>,       // address -> expiry timestamp
        
        /// Extended metadata for data discovery
        geographic_region: Option<String>,
        data_quality: Option<String>,           // "high", "medium", "low"
        sample_size: Option<u64>,
        collection_method: Option<String>,
        is_updating: bool,                      // Whether this data updates over time
        update_frequency: Option<String>,       // "daily", "weekly", "monthly"
        
        /// Version for future upgrades
        version: u64,
    }

    /// Registry for tracking MyIP ownership
    public struct MyIPRegistry has key {
        id: UID,
        ip_to_owner: Table<address, address>,
        version: u64,  // Added missing version field
    }

    // === Events ===
    
    public struct MyIPCreatedEvent has copy, drop {
        ip_id: address,
        owner: address,
        media_type: String,
        platform_id: Option<address>,
        one_time_price: Option<u64>,
        subscription_price: Option<u64>,
        created_at: u64,
    }

    public struct PurchaseEvent has copy, drop {
        ip_id: address,
        buyer: address,
        price: u64,
        purchase_type: String, // "one_time" or "subscription"
        timestamp: u64,
    }

    public struct AccessGrantedEvent has copy, drop {
        ip_id: address,
        user: address,
        access_type: String,
        granted_by: address,
        timestamp: u64,
    }

    // === Core Functions ===

    /// Bootstrap initialization function - creates the MyIP registry
    public(package) fun bootstrap_init(ctx: &mut TxContext) {
        let registry = MyIPRegistry {
            id: object::new(ctx),
            ip_to_owner: table::new(ctx),
            version: upgrade::current_version(),
        };

        transfer::share_object(registry);
    }

    /// Create new MyIP data with proper Seal encryption
    public fun create(
        media_type: String,
        tags: vector<String>,
        platform_id: Option<address>,
        timestamp_start: u64,
        timestamp_end: Option<u64>,
        encrypted_data: vector<u8>,  // Pre-encrypted data from client
        encryption_id: vector<u8>,   // Seal encryption ID
        one_time_price: Option<u64>,
        subscription_price: Option<u64>,
        subscription_duration_days: u64,
        geographic_region: Option<String>,
        data_quality: Option<String>,
        sample_size: Option<u64>,
        collection_method: Option<String>,
        is_updating: bool,
        update_frequency: Option<String>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): MyIP {
        // Input validation
        assert!(vector::length(&tags) <= MAX_TAGS, EInvalidInput);
        
        // Validate prices with overflow protection
        if (option::is_some(&one_time_price)) {
            let price_val = *option::borrow(&one_time_price);
            assert!(price_val > 0 && price_val <= MAX_U64, EInvalidInput);
        };
        
        if (option::is_some(&subscription_price)) {
            let price_val = *option::borrow(&subscription_price);
            assert!(price_val > 0 && price_val <= MAX_U64, EInvalidInput);
        };
        
        // Validate subscription duration with overflow protection
        let sub_duration = if (subscription_duration_days == 0) { 30 } else { subscription_duration_days };
        assert!(sub_duration <= MAX_SUBSCRIPTION_DAYS, EInvalidInput);
        
        // Check for potential overflow in millisecond conversion
        let duration_ms = (sub_duration as u128) * (MILLISECONDS_PER_DAY as u128);
        assert!(duration_ms <= (MAX_U64 as u128), EOverflow);
        
        // Validate time range
        if (option::is_some(&timestamp_end)) {
            let end_time = *option::borrow(&timestamp_end);
            assert!(end_time >= timestamp_start, EInvalidTimeRange);
        };
        
        let current_time = clock::timestamp_ms(clock);
        
        let myip = MyIP {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            media_type,
            tags,
            platform_id,
            timestamp_start,
            timestamp_end,
            created_at: current_time,
            last_updated: current_time,
            encrypted_data,
            encryption_id,
            one_time_price,
            subscription_price,
            subscription_duration_days: sub_duration,
            purchasers: table::new(ctx),
            subscribers: table::new(ctx),
            geographic_region,
            data_quality,
            sample_size,
            collection_method,
            is_updating,
            update_frequency,
            version: upgrade::current_version(),
        };

        let ip_id = object::uid_to_address(&myip.id);
        
        event::emit(MyIPCreatedEvent {
            ip_id,
            owner: myip.owner,
            media_type: myip.media_type,
            platform_id: myip.platform_id,
            one_time_price: myip.one_time_price,
            subscription_price: myip.subscription_price,
            created_at: myip.created_at,
        });

        myip
    }

    /// Create and share MyIP publicly
    #[allow(lint(share_owned))]
    public entry fun create_and_share(
        registry: &mut MyIPRegistry,
        media_type: String,
        tags: vector<String>,
        platform_id: Option<address>,
        timestamp_start: u64,
        timestamp_end: Option<u64>,
        encrypted_data: vector<u8>,
        encryption_id: vector<u8>,
        one_time_price: Option<u64>,
        subscription_price: Option<u64>,
        subscription_duration_days: u64,
        geographic_region: Option<String>,
        data_quality: Option<String>,
        sample_size: Option<u64>,
        collection_method: Option<String>,
        is_updating: bool,
        update_frequency: Option<String>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let myip = create(
            media_type,
            tags,
            platform_id,
            timestamp_start,
            timestamp_end,
            encrypted_data,
            encryption_id,
            one_time_price,
            subscription_price,
            subscription_duration_days,
            geographic_region,
            data_quality,
            sample_size,
            collection_method,
            is_updating,
            update_frequency,
            clock,
            ctx,
        );

        // Register in the registry
        let ip_id = object::uid_to_address(&myip.id);
        table::add(&mut registry.ip_to_owner, ip_id, myip.owner);

        transfer::share_object(myip);
    }

    /// Purchase one-time access to MyIP data
    public entry fun purchase_one_time(
        myip: &mut MyIP,
        payment: Coin<MYS>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let buyer = tx_context::sender(ctx);
        
        // Check if one-time purchase is available
        assert!(option::is_some(&myip.one_time_price), ENotForSale);
        let price = *option::borrow(&myip.one_time_price);
        
        // Check payment amount
        assert!(coin::value(&payment) >= price, EPriceMismatch);
        
        // Check if buyer already has access
        assert!(!table::contains(&myip.purchasers, buyer), EAlreadyPurchased);
        
        // Prevent self-purchase
        assert!(buyer != myip.owner, ESelfPurchase);
        
        // Handle payment
        transfer::public_transfer(payment, myip.owner);
        
        // Grant access
        table::add(&mut myip.purchasers, buyer, true);

        event::emit(PurchaseEvent {
            ip_id: object::uid_to_address(&myip.id),
            buyer,
            price,
            purchase_type: string::utf8(b"one_time"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Purchase subscription access to MyIP data
    public entry fun purchase_subscription(
        myip: &mut MyIP,
        payment: Coin<MYS>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let buyer = tx_context::sender(ctx);
        
        // Check if subscription is available
        assert!(option::is_some(&myip.subscription_price), ENotForSale);
        let price = *option::borrow(&myip.subscription_price);
        
        // Check payment amount
        assert!(coin::value(&payment) >= price, EPriceMismatch);
        
        // Prevent self-purchase
        assert!(buyer != myip.owner, ESelfPurchase);
        
        // Validate subscription duration to prevent overflow
        assert!(myip.subscription_duration_days > 0, EInvalidInput);
        assert!(myip.subscription_duration_days <= MAX_SUBSCRIPTION_DAYS, EInvalidInput);
        
        // Calculate subscription expiry safely with overflow protection
        let current_time = clock::timestamp_ms(clock);
        let duration_ms = (myip.subscription_duration_days as u128) * (MILLISECONDS_PER_DAY as u128);
        let expiry_time = (current_time as u128) + duration_ms;
        
        // Ensure we don't overflow u64
        assert!(expiry_time <= (MAX_U64 as u128), EOverflow);
        let expiry_time_u64 = expiry_time as u64;
        
        // Handle payment
        transfer::public_transfer(payment, myip.owner);
        
        // Grant/extend subscription access
        if (table::contains(&myip.subscribers, buyer)) {
            // Extend existing subscription
            let current_expiry = table::remove(&mut myip.subscribers, buyer);
            let new_expiry = if (current_expiry > current_time) {
                // Add to existing time, but check for overflow
                let extended_time = (current_expiry as u128) + duration_ms;
                assert!(extended_time <= (MAX_U64 as u128), EOverflow);
                extended_time as u64
            } else {
                expiry_time_u64
            };
            table::add(&mut myip.subscribers, buyer, new_expiry);
        } else {
            // New subscription
            table::add(&mut myip.subscribers, buyer, expiry_time_u64);
        };

        event::emit(PurchaseEvent {
            ip_id: object::uid_to_address(&myip.id),
            buyer,
            price,
            purchase_type: string::utf8(b"subscription"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Update pricing (owner only)
    public entry fun update_pricing(
        myip: &mut MyIP,
        new_one_time_price: Option<u64>,
        new_subscription_price: Option<u64>,
        new_subscription_duration_days: Option<u64>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::sender(ctx) == myip.owner, EUnauthorized);
        
        // Validate new prices
        if (option::is_some(&new_one_time_price)) {
            let price_val = *option::borrow(&new_one_time_price);
            assert!(price_val > 0, EInvalidInput);
        };
        
        if (option::is_some(&new_subscription_price)) {
            let price_val = *option::borrow(&new_subscription_price);
            assert!(price_val > 0, EInvalidInput);
        };

        myip.one_time_price = new_one_time_price;
        myip.subscription_price = new_subscription_price;
        
        if (option::is_some(&new_subscription_duration_days)) {
            let duration = *option::borrow(&new_subscription_duration_days);
            if (duration > 0) {
                myip.subscription_duration_days = duration;
            };
        };

        event::emit(AccessGrantedEvent {
            ip_id: object::uid_to_address(&myip.id),
            user: myip.owner,
            access_type: string::utf8(b"pricing_update"),
            granted_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Update MyIP content and metadata (owner only)
    public entry fun update_content(
        myip: &mut MyIP,
        new_encrypted_data: Option<vector<u8>>,
        new_tags: Option<vector<String>>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::sender(ctx) == myip.owner, EUnauthorized);
        
        if (option::is_some(&new_encrypted_data)) {
            myip.encrypted_data = *option::borrow(&new_encrypted_data);
        };
        
        if (option::is_some(&new_tags)) {
            myip.tags = *option::borrow(&new_tags);
        };
        
        myip.last_updated = clock::timestamp_ms(clock);

        event::emit(AccessGrantedEvent {
            ip_id: object::uid_to_address(&myip.id),
            user: myip.owner,
            access_type: string::utf8(b"content_update"),
            granted_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Check if user has access to MyIP data
    public fun has_access(myip: &MyIP, user: address, clock: &Clock): bool {
        // Owner always has access
        if (user == myip.owner) return true;
        
        // Check one-time purchase
        if (table::contains(&myip.purchasers, user)) return true;
        
        // Check active subscription
        if (table::contains(&myip.subscribers, user)) {
            let expiry = *table::borrow(&myip.subscribers, user);
            let current_time = clock::timestamp_ms(clock);
            return current_time <= expiry
        };
        
        false
    }

    /// Decrypt MyIP data for authorized users
    public fun decrypt_data(
        myip: &MyIP,
        viewer: address,
        clock: &Clock,
        keys: &vector<VerifiedDerivedKey>,
        pks: &vector<PublicKey>,
    ): Option<vector<u8>> {
        // Only allow access if user has direct access to this MyIP
        if (has_access(myip, viewer, clock)) {
            let obj = bf_hmac_encryption::parse_encrypted_object(myip.encrypted_data);
            return bf_hmac_encryption::decrypt(&obj, keys, pks)
        };
        
        option::none()
    }

    /// Grant free access (owner only) - useful for samples or promotions
    public entry fun grant_access(
        myip: &mut MyIP,
        user: address,
        access_type: u8, // 0 = one-time, 1 = subscription
        subscription_days: Option<u64>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::sender(ctx) == myip.owner, EUnauthorized);
        assert!(user != myip.owner, ESelfPurchase); // Owner doesn't need granted access
        
        if (access_type == 0) {
            // Grant one-time access
            if (!table::contains(&myip.purchasers, user)) {
                table::add(&mut myip.purchasers, user, true);
            };
        } else {
            // Grant subscription access
            let duration_days = if (option::is_some(&subscription_days)) {
                let days = *option::borrow(&subscription_days);
                assert!(days > 0 && days <= MAX_SUBSCRIPTION_DAYS, EInvalidInput);
                days
            } else {
                myip.subscription_duration_days
            };
            
            let current_time = clock::timestamp_ms(clock);
            let duration_ms = (duration_days as u128) * (MILLISECONDS_PER_DAY as u128);
            let expiry_time = (current_time as u128) + duration_ms;
            
            // Ensure we don't overflow u64
            assert!(expiry_time <= (MAX_U64 as u128), EOverflow);
            let expiry_time_u64 = expiry_time as u64;
            
            if (table::contains(&myip.subscribers, user)) {
                table::remove(&mut myip.subscribers, user);
            };
            table::add(&mut myip.subscribers, user, expiry_time_u64);
        };

        event::emit(AccessGrantedEvent {
            ip_id: object::uid_to_address(&myip.id),
            user,
            access_type: if (access_type == 0) { string::utf8(b"one_time") } else { string::utf8(b"subscription") },
            granted_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // === Getter Functions ===
    
    public fun owner(myip: &MyIP): address { myip.owner }
    public fun media_type(myip: &MyIP): String { myip.media_type }
    public fun tags(myip: &MyIP): vector<String> { myip.tags }
    public fun platform_id(myip: &MyIP): Option<address> { myip.platform_id }
    public fun one_time_price(myip: &MyIP): Option<u64> { myip.one_time_price }
    public fun subscription_price(myip: &MyIP): Option<u64> { myip.subscription_price }
    public fun subscription_duration_days(myip: &MyIP): u64 { myip.subscription_duration_days }
    public fun created_at(myip: &MyIP): u64 { myip.created_at }
    public fun last_updated(myip: &MyIP): u64 { myip.last_updated }
    public fun timestamp_start(myip: &MyIP): u64 { myip.timestamp_start }
    public fun timestamp_end(myip: &MyIP): Option<u64> { myip.timestamp_end }
    public fun geographic_region(myip: &MyIP): Option<String> { myip.geographic_region }
    public fun data_quality(myip: &MyIP): Option<String> { myip.data_quality }
    public fun sample_size(myip: &MyIP): Option<u64> { myip.sample_size }
    public fun collection_method(myip: &MyIP): Option<String> { myip.collection_method }
    public fun is_updating(myip: &MyIP): bool { myip.is_updating }
    public fun update_frequency(myip: &MyIP): Option<String> { myip.update_frequency }
    public fun purchaser_count(myip: &MyIP): u64 { table::length(&myip.purchasers) }
    public fun subscriber_count(myip: &MyIP): u64 { table::length(&myip.subscribers) }
    public fun is_one_time_for_sale(myip: &MyIP): bool { option::is_some(&myip.one_time_price) }
    public fun is_subscription_available(myip: &MyIP): bool { option::is_some(&myip.subscription_price) }

    /// Check if a user has an active subscription
    public fun has_active_subscription(myip: &MyIP, user: address, clock: &Clock): bool {
        if (!table::contains(&myip.subscribers, user)) return false;
        let expiry = *table::borrow(&myip.subscribers, user);
        let current_time = clock::timestamp_ms(clock);
        current_time <= expiry
    }

    /// Get subscription expiry time for a user
    public fun get_subscription_expiry(myip: &MyIP, user: address): Option<u64> {
        if (table::contains(&myip.subscribers, user)) {
            option::some(*table::borrow(&myip.subscribers, user))
        } else {
            option::none()
        }
    }

    /// Get total revenue potential (for analytics) with overflow protection
    public fun get_revenue_potential(myip: &MyIP): u64 {
        let one_time_revenue = if (option::is_some(&myip.one_time_price)) {
            let price = *option::borrow(&myip.one_time_price);
            let count = table::length(&myip.purchasers);
            // Use u128 for calculation to detect overflow
            let revenue = (price as u128) * (count as u128);
            if (revenue > (MAX_U64 as u128)) {
                MAX_U64
            } else {
                revenue as u64
            }
        } else {
            0
        };
        
        let subscription_revenue = if (option::is_some(&myip.subscription_price)) {
            let price = *option::borrow(&myip.subscription_price);
            let count = table::length(&myip.subscribers);
            // Use u128 for calculation to detect overflow
            let revenue = (price as u128) * (count as u128);
            if (revenue > (MAX_U64 as u128)) {
                MAX_U64
            } else {
                revenue as u64
            }
        } else {
            0
        };
        
        // Safe addition with overflow protection
        let total_revenue = (one_time_revenue as u128) + (subscription_revenue as u128);
        if (total_revenue > (MAX_U64 as u128)) {
            MAX_U64
        } else {
            total_revenue as u64
        }
    }

    /// Check if MyIP has any sales (one-time or subscription)
    public fun has_any_sales(myip: &MyIP): bool {
        table::length(&myip.purchasers) > 0 || table::length(&myip.subscribers) > 0
    }

    // === Registry Functions ===
    
    /// Get owner of a MyIP by ID
    public fun registry_get_owner(registry: &MyIPRegistry, ip_id: address): Option<address> {
        if (table::contains(&registry.ip_to_owner, ip_id)) {
            option::some(*table::borrow(&registry.ip_to_owner, ip_id))
        } else {
            option::none()
        }
    }

    /// Check if a MyIP is registered
    public fun is_registered(registry: &MyIPRegistry, ip_id: address): bool {
        table::contains(&registry.ip_to_owner, ip_id)
    }

    /// Register a MyIP in the registry
    public entry fun register_in_registry(
        registry: &mut MyIPRegistry,
        myip: &MyIP,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::sender(ctx) == myip.owner, EUnauthorized);
        let ip_id = object::uid_to_address(&myip.id);
        
        if (!table::contains(&registry.ip_to_owner, ip_id)) {
            table::add(&mut registry.ip_to_owner, ip_id, myip.owner);
        };
    }

    /// Remove a MyIP from the registry
    public entry fun unregister_from_registry(
        registry: &mut MyIPRegistry,
        ip_id: address,
        ctx: &mut TxContext,
    ) {
        if (table::contains(&registry.ip_to_owner, ip_id)) {
            let owner = *table::borrow(&registry.ip_to_owner, ip_id);
            assert!(tx_context::sender(ctx) == owner, EUnauthorized);
            table::remove(&mut registry.ip_to_owner, ip_id);
        };
    }

    // === Versioning Functions ===
    
    public fun version(myip: &MyIP): u64 {
        myip.version
    }

    public fun borrow_version_mut(myip: &mut MyIP): &mut u64 {
        &mut myip.version
    }

    public fun registry_version(registry: &MyIPRegistry): u64 {
        registry.version
    }

    public fun borrow_registry_version_mut(registry: &mut MyIPRegistry): &mut u64 {
        &mut registry.version
    }

    /// Migration function for MyIP
    public entry fun migrate_my_ip(
        myip: &mut MyIP,
        _: &UpgradeAdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        assert!(myip.version < current_version, EInvalidInput);
        
        let old_version = myip.version;
        myip.version = current_version;
        
        let myip_id = object::id(myip);
        upgrade::emit_migration_event(
            myip_id,
            string::utf8(b"MyIP"),
            old_version,
            tx_context::sender(ctx)
        );
    }

    /// Migration function for MyIPRegistry
    public entry fun migrate_registry(
        registry: &mut MyIPRegistry,
        _: &UpgradeAdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        assert!(registry.version < current_version, EInvalidInput);
        
        let old_version = registry.version;
        registry.version = current_version;
        
        let registry_id = object::id(registry);
        upgrade::emit_migration_event(
            registry_id,
            string::utf8(b"MyIPRegistry"),
            old_version,
            tx_context::sender(ctx)
        );
    }

    // === Test Functions ===

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        let registry = MyIPRegistry {
            id: object::new(ctx),
            ip_to_owner: table::new(ctx),
            version: upgrade::current_version(),
        };
        transfer::share_object(registry);
    }

    #[test_only]
    public fun test_destroy(myip: MyIP) {
        let MyIP { 
            id, owner: _, media_type: _, tags: _, platform_id: _,
            timestamp_start: _, timestamp_end: _, created_at: _, last_updated: _,
            encrypted_data: _, encryption_id: _, one_time_price: _, subscription_price: _,
            subscription_duration_days: _, purchasers, subscribers, geographic_region: _,
            data_quality: _, sample_size: _, collection_method: _, is_updating: _,
            update_frequency: _, version: _
        } = myip;
        table::drop(purchasers);
        table::drop(subscribers);
        object::delete(id);
    }
}
