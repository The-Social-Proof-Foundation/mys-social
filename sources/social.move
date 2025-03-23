// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Main social network module for MySocial
/// Entry point for initializing all social network components
module social_contracts::social {
    use mys::tx_context::{Self, TxContext};

    use social_contracts::social_graph;
    use social_contracts::reputation;
    use social_contracts::platform;

    /// Initialize all social network components
    /// This should be called once during system initialization
    public entry fun initialize(ctx: &mut TxContext) {
        // Initialize global social graph
        social_graph::initialize(ctx);
        
        // Initialize reputation system
        reputation::initialize(ctx);
        
        // Initialize platform registry
        platform::initialize(ctx);
    }
}