// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Module to manage package upgrades for MySocialContracts.
/// Provides versioning support for all shared objects.

module social_contracts::upgrade {
    use std::string::String;
    use mys::package;
    use mys::event;
    
    // Error codes
    const EInvalidDigest: u64 = 0;
    const EWrongVersion: u64 = 1;

    // Current package version - increment with each upgrade
    const CURRENT_VERSION: u64 = 1;

    // Object type constants removed to avoid dependencies

    /// Admin capability for package upgrades
    public struct AdminCap has key, store {
        id: object::UID
    }

    /// Event emitted when a package is upgraded
    public struct UpgradeEvent has copy, drop {
        package_id: object::ID,
        version: u64
    }

    /// Event emitted when a shared object is migrated to a new version
    public struct ObjectMigratedEvent has copy, drop {
        object_id: ID,
        object_type: String,
        old_version: u64,
        new_version: u64,
        migrated_by: address
    }

    /// Module initializer - runs once when the package is published
    fun init(ctx: &mut tx_context::TxContext) {
        // Get the publisher (sender of the publish transaction)
        let publisher = tx_context::sender(ctx);
        
        // Create admin capability
        let admin_cap = AdminCap {
            id: object::new(ctx)
        };
        
        // Transfer admin capability to publisher
        transfer::transfer(admin_cap, publisher);
        
        // The UpgradeCap will be automatically transferred to the publisher
        // by the MySocial system when the package is published
    }

    /// Authorize an upgrade with the upgrade cap
    public fun authorize_upgrade(
        cap: &mut package::UpgradeCap, 
        digest: vector<u8>
    ): package::UpgradeTicket {
        // Verify digest length is 32 bytes
        assert!(vector::length(&digest) == 32, EInvalidDigest);
        
        // Use default upgrade policy
        let policy = cap.policy();
        
        // Return the upgrade ticket
        cap.authorize_upgrade(policy, digest)
    }

    /// Commit an upgrade with the receipt
    public fun commit_upgrade(
        cap: &mut package::UpgradeCap, 
        receipt: package::UpgradeReceipt
    ) {
        // Emit upgrade event
        event::emit(UpgradeEvent {
            package_id: receipt.package(),
            version: cap.version() + 1
        });
        
        // Commit the upgrade
        cap.commit_upgrade(receipt);
    }

    /// Get the current package version
    public fun version(cap: &package::UpgradeCap): u64 {
        cap.version()
    }

    /// Get the package ID
    public fun package_id(cap: &package::UpgradeCap): object::ID {
        cap.package()
    }

    /// Get the current package version constant
    public fun current_version(): u64 {
        CURRENT_VERSION
    }

    /// Check if the version matches the current package version
    public fun assert_version(version: u64) {
        assert!(version == CURRENT_VERSION, EWrongVersion);
    }

    /// Helper function to emit migration event
    /// This can be called directly by other modules implementing their own migration
    public fun emit_migration_event(
        object_id: ID,
        object_type: String,
        old_version: u64,
        migrated_by: address
    ) {
        event::emit(ObjectMigratedEvent {
            object_id,
            object_type,
            old_version,
            new_version: CURRENT_VERSION,
            migrated_by
        });
    }
    
    // Test utilities
    #[test_only]
    public fun create_test_digest(bytes: vector<u8>): vector<u8> {
        let mut res = bytes;
        
        // Ensure the digest is exactly 32 bytes
        if (vector::length(&res) < 32) {
            // Pad with zeros
            while (vector::length(&res) < 32) {
                vector::push_back(&mut res, 0);
            };
        } else if (vector::length(&res) > 32) {
            // Truncate to 32 bytes
            let mut truncated = vector::empty();
            let mut i = 0;
            while (i < 32) {
                vector::push_back(&mut truncated, *vector::borrow(&res, i));
                i = i + 1;
            };
            res = truncated;
        };
        
        res
    }
} 