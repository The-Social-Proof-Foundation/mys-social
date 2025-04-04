// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Standardized event structures for MySocial platform
module social_contracts::events {
    use std::string::{Self, String};
    use mys::object::{Self, ID};
    use mys::event;
    
    // === Platform Events ===
    
    /// Base event with common fields for all platform events
    public struct BaseEvent has copy, drop {
        timestamp: u64,
        // Optional metadata for events
        category: String,
        // Optional version for event schema evolution
        version: u8,
    }
    
    /// Event emitted when a new entity is created
    public struct EntityCreatedEvent has copy, drop {
        base: BaseEvent,
        entity_type: String,
        entity_id: ID,
        creator: address,
    }
    
    /// Event emitted when an entity is updated
    public struct EntityUpdatedEvent has copy, drop {
        base: BaseEvent,
        entity_type: String,
        entity_id: ID,
        updater: address,
        update_type: String,
    }
    
    /// Event emitted when an entity is deleted
    public struct EntityDeletedEvent has copy, drop {
        base: BaseEvent,
        entity_type: String,
        entity_id: ID,
        deleter: address,
        reason: String,
    }
    
    // === Platform-specific Events ===
    
    /// Event emitted when a new platform is created
    public struct PlatformCreatedEvent has copy, drop {
        base: BaseEvent,
        platform_id: ID,
        name: String,
        owner: address,
        category: String,
    }
    
    /// Event emitted when a platform's reputation changes
    public struct ReputationChangedEvent has copy, drop {
        base: BaseEvent,
        entity_id: ID,
        entity_type: String, // "platform" or "user"
        old_score: u64,
        new_score: u64,
        reason: String,
        reason_code: u8,
    }
    
    /// Event emitted when a token is created
    public struct TokenCreatedEvent has copy, drop {
        base: BaseEvent,
        token_id: address,
        name: String,
        symbol: String,
        is_platform_token: bool,
        owner: address,
        supply_cap: u64,
    }
    
    /// Event emitted when token supply changes
    public struct TokenSupplyChangedEvent has copy, drop {
        base: BaseEvent,
        token_id: address,
        owner: address,
        old_supply: u64,
        new_supply: u64,
        reason: String,
    }
    
    /// Event emitted for token transfers
    public struct TokenTransferEvent has copy, drop {
        base: BaseEvent,
        token_id: address,
        from: address,
        to: address,
        amount: u64,
    }
    
    /// Event emitted for token trades
    public struct TokenTradeEvent has copy, drop {
        base: BaseEvent,
        base_token_id: address,
        quote_token_id: address,
        trader: address,
        is_buy: bool,
        price: u64,
        amount: u64,
        fee: u64,
    }
    
    /// Event emitted when a post is created
    public struct PostCreatedEvent has copy, drop {
        base: BaseEvent,
        post_id: ID,
        platform_id: ID,
        author: address,
        has_media: bool,
        content_hash: vector<u8>,
    }
    
    /// Event emitted for post engagements
    public struct PostEngagementEvent has copy, drop {
        base: BaseEvent,
        post_id: ID,
        user: address,
        engagement_type: String, // "like", "comment", "share", etc.
        platform_id: ID,
    }
    
    // === Event Creation Functions ===
    
    /// Create a base event with common fields
    public fun create_base_event(
        timestamp: u64,
        category: vector<u8>,
        version: u8
    ): BaseEvent {
        BaseEvent {
            timestamp,
            category: string::utf8(category),
            version,
        }
    }
    
    /// Emit an entity created event
    public fun emit_entity_created(
        timestamp: u64,
        entity_type: vector<u8>,
        entity_id: ID,
        creator: address
    ) {
        let base = create_base_event(timestamp, b"entity", 1);
        event::emit(EntityCreatedEvent {
            base,
            entity_type: string::utf8(entity_type),
            entity_id,
            creator,
        });
    }
    
    /// Emit a platform created event
    public fun emit_platform_created(
        timestamp: u64,
        platform_id: ID,
        name: vector<u8>,
        owner: address,
        category: vector<u8>
    ) {
        let base = create_base_event(timestamp, b"platform", 1);
        event::emit(PlatformCreatedEvent {
            base,
            platform_id,
            name: string::utf8(name),
            owner,
            category: string::utf8(category),
        });
    }
    
    /// Emit a reputation changed event
    public fun emit_reputation_changed(
        timestamp: u64,
        entity_id: ID,
        entity_type: vector<u8>,
        old_score: u64,
        new_score: u64,
        reason: vector<u8>,
        reason_code: u8
    ) {
        let base = create_base_event(timestamp, b"reputation", 1);
        event::emit(ReputationChangedEvent {
            base,
            entity_id,
            entity_type: string::utf8(entity_type),
            old_score,
            new_score,
            reason: string::utf8(reason),
            reason_code,
        });
    }
    
    /// Emit a token created event
    public fun emit_token_created(
        timestamp: u64,
        token_id: address,
        name: vector<u8>,
        symbol: vector<u8>,
        is_platform_token: bool,
        owner: address,
        supply_cap: u64
    ) {
        let base = create_base_event(timestamp, b"token", 1);
        event::emit(TokenCreatedEvent {
            base,
            token_id,
            name: string::utf8(name),
            symbol: string::utf8(symbol),
            is_platform_token,
            owner,
            supply_cap,
        });
    }
    
    /// Emit a token supply changed event
    public fun emit_token_supply_changed(
        timestamp: u64,
        token_id: address,
        owner: address,
        old_supply: u64,
        new_supply: u64,
        reason: vector<u8>
    ) {
        let base = create_base_event(timestamp, b"token", 1);
        event::emit(TokenSupplyChangedEvent {
            base,
            token_id,
            owner,
            old_supply,
            new_supply,
            reason: string::utf8(reason),
        });
    }
    
    /// Emit a post created event
    public fun emit_post_created(
        timestamp: u64,
        post_id: ID,
        platform_id: ID,
        author: address,
        has_media: bool,
        content_hash: vector<u8>
    ) {
        let base = create_base_event(timestamp, b"post", 1);
        event::emit(PostCreatedEvent {
            base,
            post_id,
            platform_id,
            author,
            has_media,
            content_hash,
        });
    }
    
    /// Emit a post engagement event
    public fun emit_post_engagement(
        timestamp: u64,
        post_id: ID,
        user: address,
        engagement_type: vector<u8>,
        platform_id: ID
    ) {
        let base = create_base_event(timestamp, b"engagement", 1);
        event::emit(PostEngagementEvent {
            base,
            post_id,
            user,
            engagement_type: string::utf8(engagement_type),
            platform_id,
        });
    }
}