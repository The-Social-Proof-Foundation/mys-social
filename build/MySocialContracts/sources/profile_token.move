// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Integration module that connects user profiles with their tokens
module social_contracts::profile_token {
    use std::string;
    use std::option::{Self, Option};
    use mys::object::{Self, UID};
    use mys::transfer;
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use social_contracts::user_token::{Self, AdminCap, TokenRegistry};
    use mys::coin::{Self, TreasuryCap, CoinMetadata};
    use mys::url::{Self, Url};
    
    // === Errors ===
    /// Operation can only be performed by the platform admin
    const ENotAuthorized: u64 = 0;
    /// Profile does not exist
    const EProfileNotFound: u64 = 1;
    /// Token already exists for this profile
    const ETokenAlreadyExists: u64 = 2;
    /// Token does not exist for this profile
    const ETokenNotExists: u64 = 3;
    
    // === Structs ===
    
    /// Profile Token Manager - connects profile IDs to tokens
    /// Shared object that stores the mapping
    public struct ProfileTokenManager has key {
        id: UID,
        // We use the profile's creator address as the key
        // This assumes that profile creation already enforces uniqueness
    }
    
    /// Request to create a token for a profile
    /// Created by a user and approved by admin
    public struct TokenCreationRequest has key, store {
        id: UID,
        creator: address,
        profile_id: address, // The profile identifier
        symbol: string::String,
        name: string::String,
        description: string::String,
        icon_url: Option<Url>,
        commission_bps: u64,
        creator_split_bps: u64,
    }
    
    // === Events ===
    
    /// Event emitted when a token creation request is submitted
    public struct TokenRequestCreatedEvent has copy, drop {
        request_id: address,
        creator: address,
        profile_id: address,
        symbol: string::String,
        name: string::String,
    }
    
    /// Event emitted when a profile token is created
    public struct ProfileTokenCreatedEvent has copy, drop {
        profile_id: address,
        creator: address,
        token_id: address,
        symbol: string::String,
        name: string::String,
    }
    
    // === Initialization ===
    
    /// Initialize the profile token integration
    fun init(ctx: &mut TxContext) {
        // Create and share profile token manager
        transfer::share_object(
            ProfileTokenManager {
                id: object::new(ctx),
            }
        );
    }
    
    // === User Functions ===
    
    /// Create a request for a profile token
    /// This request must be approved by the admin
    public entry fun create_token_request(
        profile_id: address,
        symbol: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        has_icon_url: bool,
        icon_url_bytes: vector<u8>,
        commission_bps: u64,
        creator_split_bps: u64,
        ctx: &mut TxContext
    ) {
        // Convert inputs to the right format
        let symbol_str = string::utf8(symbol);
        let name_str = string::utf8(name);
        let description_str = string::utf8(description);
        
        // Create the request object
        let request = TokenCreationRequest {
            id: object::new(ctx),
            creator: tx_context::sender(ctx),
            profile_id,
            symbol: symbol_str,
            name: name_str,
            description: description_str,
            icon_url: if (has_icon_url) { 
                option::some(url::new_unsafe_from_bytes(icon_url_bytes)) 
            } else { 
                option::none() 
            },
            commission_bps,
            creator_split_bps,
        };
        
        // Emit event
        event::emit(TokenRequestCreatedEvent {
            request_id: object::uid_to_address(&request.id),
            creator: request.creator,
            profile_id: request.profile_id,
            symbol: request.symbol,
            name: request.name,
        });
        
        // Transfer the request to admin
        // In a real implementation, you would transfer to a known admin address
        // or use a shared object queue for requests
        transfer::transfer(request, tx_context::sender(ctx));
    }
    
    // === Admin Functions ===
    
    /// Approve a token request and create the token
    /// This can only be called by the admin
    public entry fun approve_token_request<TOKEN: drop>(
        admin_cap: &AdminCap,
        registry: &mut TokenRegistry,
        request: TokenCreationRequest,
        witness: TOKEN,
        decimals: u8,
        ctx: &mut TxContext
    ) {
        // Extract request information
        let TokenCreationRequest {
            id,
            creator,
            profile_id,
            symbol,
            name,
            description,
            icon_url,
            commission_bps,
            creator_split_bps
        } = request;
        
        // Clean up request ID
        object::delete(id);
        
        // Check if user already has a token
        assert!(!user_token::has_token(registry, creator), ETokenAlreadyExists);
        
        // Extract icon URL bytes if present
        // For simplicity, we'll skip icon URL extraction in this implementation
        let has_icon_url = option::is_some(&icon_url);
        let icon_url_bytes = b""; // Empty bytes to simplify implementation
        
        // Create the user token with raw bytes from strings - convert to raw vectors
        let symbol_bytes = string::bytes(&symbol);
        let name_bytes = string::bytes(&name);
        let desc_bytes = string::bytes(&description);
        
        // Create a copy of each vector to pass as values, not references
        // Copy each byte from the references to new vectors
        let symbol_bytes_ref = string::bytes(&symbol);
        let name_bytes_ref = string::bytes(&name);
        let desc_bytes_ref = string::bytes(&description);
        
        let mut symbol_vec = vector::empty<u8>();
        let mut name_vec = vector::empty<u8>();
        let mut desc_vec = vector::empty<u8>();
        
        let mut i = 0;
        let len = vector::length(symbol_bytes_ref);
        while (i < len) {
            vector::push_back(&mut symbol_vec, *vector::borrow(symbol_bytes_ref, i));
            i = i + 1;
        };
        
        let mut i = 0;
        let len = vector::length(name_bytes_ref);
        while (i < len) {
            vector::push_back(&mut name_vec, *vector::borrow(name_bytes_ref, i));
            i = i + 1;
        };
        
        let mut i = 0;
        let len = vector::length(desc_bytes_ref);
        while (i < len) {
            vector::push_back(&mut desc_vec, *vector::borrow(desc_bytes_ref, i));
            i = i + 1;
        };
        
        // Create the user token
        user_token::create_user_token<TOKEN>(
            admin_cap,
            registry,
            creator,
            witness,
            decimals,
            symbol_vec,
            name_vec,
            desc_vec,
            has_icon_url,
            icon_url_bytes,
            true, // has_commission
            commission_bps,
            true, // has_creator_split
            creator_split_bps,
            ctx
        );
        
        // Emit event for profile token creation
        event::emit(ProfileTokenCreatedEvent {
            profile_id,
            creator,
            token_id: @0x0, // placeholder token ID - in production this would be derived from TOKEN type
            symbol,
            name,
        });
    }
    
    /// Create tokens for a profile directly without request
    /// Admin-only function for expedited token creation
    public entry fun create_profile_token<TOKEN: drop>(
        admin_cap: &AdminCap,
        registry: &mut TokenRegistry,
        profile_id: address,
        creator: address,
        witness: TOKEN,
        decimals: u8,
        symbol: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        has_icon_url: bool,
        icon_url_bytes: vector<u8>,
        commission_bps: u64,
        creator_split_bps: u64,
        ctx: &mut TxContext
    ) {
        // Check if user already has a token
        assert!(!user_token::has_token(registry, creator), ETokenAlreadyExists);
        
        // Create the user token with raw bytes
        user_token::create_user_token<TOKEN>(
            admin_cap,
            registry,
            creator,
            witness, // One-time witness passed from parameter
            decimals,
            symbol, // Already vector<u8>
            name, // Already vector<u8>
            description, // Already vector<u8>
            has_icon_url,
            icon_url_bytes,
            true, // has_commission
            commission_bps,
            true, // has_creator_split
            creator_split_bps,
            ctx
        );
        
        // Convert inputs for the event
        let symbol_str = string::utf8(symbol);
        let name_str = string::utf8(name);
        
        // Emit event for profile token creation
        event::emit(ProfileTokenCreatedEvent {
            profile_id,
            creator,
            token_id: @0x0, // placeholder token ID - in production this would be derived from TOKEN type
            symbol: symbol_str,
            name: name_str,
        });
    }
    
    /// Mint tokens for initial distribution (admin only)
    public entry fun mint_profile_tokens<T>(
        admin_cap: &AdminCap,
        treasury_cap: &mut TreasuryCap<T>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        // Mint tokens for initial distribution or liquidity
        user_token::mint_tokens(
            admin_cap,
            treasury_cap,
            amount,
            recipient,
            ctx
        );
    }
    
    // === Helper Functions ===
    
    /// Check if a profile has a token
    public fun has_profile_token(
        registry: &TokenRegistry,
        creator: address
    ): bool {
        user_token::has_token(registry, creator)
    }
    
    /// Get profile token info
    public fun get_profile_token_info(
        registry: &TokenRegistry,
        creator: address
    ): (bool, address, u64, u64, u64) {
        let (has_token, token_info) = user_token::get_user_token_info(registry, creator);
        if (has_token) {
            (
                true,
                user_token::token_id(&token_info),
                user_token::commission_bps(&token_info),
                user_token::creator_split_bps(&token_info),
                user_token::platform_split_bps(&token_info)
            )
        } else {
            (false, @0x0, 0, 0, 0)
        }
    }
}