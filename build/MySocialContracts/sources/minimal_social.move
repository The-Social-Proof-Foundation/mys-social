// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Minimal Social module for building and testing purposes
module social_contracts::minimal_social {
    use std::string;
    use mys::object;
    use mys::tx_context;
    use mys::transfer;

    /// A basic struct to test compilation
    public struct BasicProfile has key, store {
        id: object::UID,
        name: string::String,
    }

    /// Initialize function
    public entry fun initialize(_ctx: &mut tx_context::TxContext) {
        // This is a placeholder for initialization
    }

    /// Create a basic profile
    public entry fun create_profile(
        name: string::String,
        ctx: &mut tx_context::TxContext
    ) {
        let profile = BasicProfile {
            id: object::new(ctx),
            name
        };
        
        let sender = tx_context::sender(ctx);
        transfer::transfer(profile, sender);
    }
} 