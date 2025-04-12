// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Post module for the MySocial network
/// Handles creation and management of posts and comments
#[allow(unused_const, duplicate_alias, unused_use, unused_variable)]
module social_contracts::post {
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    
    use mys::object::{Self, UID, ID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer;
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::mys::MYS;
    use mys::url::{Self, Url};
    use mys::package::{Self, Publisher};
    
    use social_contracts::profile::{Self, Profile, UsernameRegistry};
    use social_contracts::platform;

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EPostNotFound: u64 = 1;
    const EInvalidTipAmount: u64 = 4;
    const ESelfTipping: u64 = 5;
    const EInvalidParentReference: u64 = 6;
    const EContentTooLarge: u64 = 7;
    const ETooManyMediaUrls: u64 = 8;
    const EInvalidPostType: u64 = 9;
    const EUnauthorizedTransfer: u64 = 10;
    const EReportReasonInvalid: u64 = 12;
    const EReportDescriptionTooLong: u64 = 13;
    const EReactionContentTooLong: u64 = 14;

    /// Constants for size limits
    const MAX_CONTENT_LENGTH: u64 = 5000; // 5000 chars max for content
    const MAX_MEDIA_URLS: u64 = 10; // Max 10 media URLs per post
    const MAX_MENTIONS: u64 = 10; // Max 50 mentions per post
    const MAX_METADATA_SIZE: u64 = 10000; // 10KB max for metadata
    const MAX_DESCRIPTION_LENGTH: u64 = 500; // 500 chars max for report description
    const MAX_REACTION_LENGTH: u64 = 20; // 50 chars max for a reaction
    const COMMENTER_TIP_PERCENTAGE: u64 = 80; // 80% of tip goes to commenter, 20% to post owner
    const REPOST_TIP_PERCENTAGE: u64 = 50; // 50% of tip goes to repost owner, 50% to original post owner

    /// Valid post types
    const POST_TYPE_STANDARD: vector<u8> = b"standard";
    const POST_TYPE_REPOST: vector<u8> = b"repost";
    const POST_TYPE_QUOTE_REPOST: vector<u8> = b"quote_repost";

    /// Constants for report reason codes
    const REPORT_REASON_SPAM: u8 = 1;
    const REPORT_REASON_OFFENSIVE: u8 = 2;
    const REPORT_REASON_MISINFORMATION: u8 = 3;
    const REPORT_REASON_ILLEGAL: u8 = 4;
    const REPORT_REASON_IMPERSONATION: u8 = 5;
    const REPORT_REASON_HARASSMENT: u8 = 6;
    const REPORT_REASON_OTHER: u8 = 99;

    /// Post object that contains content information
    public struct Post has key, store {
        id: UID,
        /// Owner's wallet address (the true owner)
        owner: address,
        /// Author's profile ID (reference only, not ownership)
        profile_id: address,
        /// Post content
        content: String,
        /// Optional media URLs (multiple supported)
        media: Option<vector<Url>>,
        /// Optional mentioned users (profile IDs)
        mentions: Option<vector<address>>,
        /// Optional metadata in JSON format
        metadata_json: Option<String>,
        /// Post type (standard, comment, repost, quote_repost)
        post_type: String,
        /// Optional parent post ID for replies or quote reposts
        parent_post_id: Option<address>,
        /// Creation timestamp
        created_at: u64,
        /// Total number of reactions
        reaction_count: u64,
        /// Number of comments
        comment_count: u64,
        /// Number of reposts
        repost_count: u64,
        /// Total tips received in MYS (tracking only, not actual balance)
        tips_received: u64,
        /// Whether the post has been removed from its platform
        removed_from_platform: bool,
        /// Table of user wallet addresses to their reactions (emoji or text)
        user_reactions: Table<address, String>,
        /// Table to count reactions by type
        reaction_counts: Table<String, u64>,
    }

    /// Comment object for posts, supporting nested comments
    public struct Comment has key, store {
        id: UID,
        /// The post this comment belongs to
        post_id: address,
        /// Optional parent comment ID for nested comments
        parent_comment_id: Option<address>,
        /// Owner's wallet address (the true owner)
        owner: address,
        /// Commenter's profile ID (reference only, not ownership)
        profile_id: address,
        /// Comment content
        content: String,
        /// Optional media URLs
        media: Option<vector<Url>>,
        /// Optional mentioned users (profile IDs)
        mentions: Option<vector<address>>,
        /// Optional metadata in JSON format
        metadata_json: Option<String>,
        /// Creation timestamp
        created_at: u64,
        /// Total number of reactions
        reaction_count: u64,
        /// Number of nested comments
        comment_count: u64,
        /// Number of reposts
        repost_count: u64,
        /// Total tips received in MYS (tracking only, not actual balance)
        tips_received: u64,
        /// Whether the comment has been removed from its platform
        removed_from_platform: bool,
        /// Table of user wallet addresses to their reactions (emoji or text)
        user_reactions: Table<address, String>,
        /// Table to count reactions by type
        reaction_counts: Table<String, u64>,
    }

    /// Repost reference
    public struct Repost has key, store {
        id: UID,
        /// The post/comment being reposted
        original_id: address,
        /// Whether the original is a post (true) or comment (false)
        is_original_post: bool,
        /// Owner's wallet address (the true owner)
        owner: address,
        /// Reposter's profile ID (reference only, not ownership)
        profile_id: address,
        /// Creation timestamp
        created_at: u64,
    }

    /// Post created event
    public struct PostCreatedEvent has copy, drop {
        post_id: address,
        owner: address,
        profile_id: address,
        content: String,
        post_type: String,
        parent_post_id: Option<address>,
        mentions: Option<vector<address>>,
    }

    /// Comment created event
    public struct CommentCreatedEvent has copy, drop {
        comment_id: address,
        post_id: address,
        parent_comment_id: Option<address>,
        owner: address,
        profile_id: address,
        content: String,
        mentions: Option<vector<address>>,
    }

    /// Repost event
    public struct RepostEvent has copy, drop {
        repost_id: address,
        original_id: address,
        is_original_post: bool,
        owner: address,
        profile_id: address,
    }

    /// Reaction event
    public struct ReactionEvent has copy, drop {
        object_id: address,
        user: address,
        reaction: String,
        is_post: bool,
    }

    /// Remove reaction event
    public struct RemoveReactionEvent has copy, drop {
        object_id: address,
        user: address,
        reaction: String,
        is_post: bool,
    }

    /// Tip event
    public struct TipEvent has copy, drop {
        tipper: address,
        recipient: address,
        object_id: address, 
        amount: u64,
        is_post: bool,
    }

    /// Post ownership transfer event
    public struct OwnershipTransferEvent has copy, drop {
        object_id: address,
        previous_owner: address,
        new_owner: address,
        is_post: bool,
    }

    /// Post moderation event
    public struct PostModerationEvent has copy, drop {
        post_id: address,
        platform_id: address,
        removed: bool,
        moderated_by: address,
    }

    /// Post updated event
    public struct PostUpdatedEvent has copy, drop {
        post_id: address,
        owner: address,
        profile_id: address,
        content: String,
        metadata_json: Option<String>,
        updated_at: u64,
    }

    /// Comment updated event 
    public struct CommentUpdatedEvent has copy, drop {
        comment_id: address,
        post_id: address,
        owner: address,
        profile_id: address,
        content: String,
        updated_at: u64,
    }

    /// Post reported event
    public struct PostReportedEvent has copy, drop {
        post_id: address,
        reporter: address,
        reason_code: u8,
        description: String,
        reported_at: u64,
    }

    /// Comment reported event
    public struct CommentReportedEvent has copy, drop {
        comment_id: address,
        reporter: address,
        reason_code: u8,
        description: String,
        reported_at: u64,
    }

    /// Post deleted event
    public struct PostDeletedEvent has copy, drop {
        post_id: address,
        owner: address,
        profile_id: address,
        post_type: String,
        deleted_at: u64,
    }
    
    /// Comment deleted event
    public struct CommentDeletedEvent has copy, drop {
        comment_id: address,
        post_id: address,
        owner: address,
        profile_id: address,
        deleted_at: u64,
    }

    /// Internal function to create a post and return its ID
    fun create_post_internal(
        owner: address,
        profile_id: address,
        content: String,
        media_option: Option<vector<Url>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        post_type: String,
        parent_post_id: Option<address>,
        ctx: &mut TxContext
    ): address {
        let post = Post {
            id: object::new(ctx),
            owner,
            profile_id,
            content,
            media: media_option,
            mentions,
            metadata_json,
            post_type,
            parent_post_id,
            created_at: tx_context::epoch(ctx),
            reaction_count: 0,
            comment_count: 0,
            repost_count: 0,
            tips_received: 0,
            removed_from_platform: false,
            user_reactions: table::new(ctx),
            reaction_counts: table::new(ctx),
        };
        
        // Get post ID before sharing
        let post_id = object::uid_to_address(&post.id);
        
        // Share object
        transfer::share_object(post);
        
        // Return the post ID
        post_id
    }

    /// Create a new post
    public entry fun create_post(
        registry: &UsernameRegistry,
        content: String,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        
        // Look up the profile ID for the sender (for reference, not ownership)
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let profile_id = option::extract(&mut profile_id_option);
        
        // Validate content length
        assert!(string::length(&content) <= MAX_CONTENT_LENGTH, EContentTooLarge);
        
        // Validate metadata size if provided
        if (option::is_some(&metadata_json)) {
            let metadata_ref = option::borrow(&metadata_json);
            assert!(string::length(metadata_ref) <= MAX_METADATA_SIZE, EContentTooLarge);
        };
        
        // Convert and validate media URLs if provided
        let media_option = if (option::is_some(&media_urls)) {
            let urls_bytes = option::extract(&mut media_urls);
            
            // Validate media URLs count
            assert!(vector::length(&urls_bytes) <= MAX_MEDIA_URLS, ETooManyMediaUrls);
            
            // Convert media URL bytes to Url
            let mut urls = vector::empty<Url>();
            let mut i = 0;
            let len = vector::length(&urls_bytes);
            while (i < len) {
                let url_bytes = *vector::borrow(&urls_bytes, i);
                vector::push_back(&mut urls, url::new_unsafe_from_bytes(url_bytes));
                i = i + 1;
            };
            option::some(urls)
        } else {
            option::none<vector<Url>>()
        };
        
        // Validate mentions if provided
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= MAX_MENTIONS, EContentTooLarge);
        };
        
        // Create and share the post
        let post_id = create_post_internal(
            owner,
            profile_id,
            content,
            media_option,
            mentions,
            metadata_json,
            string::utf8(POST_TYPE_STANDARD),
            option::none(),
            ctx
        );
        
        // Emit post created event
        event::emit(PostCreatedEvent {
            post_id,
            owner,
            profile_id,
            content,
            post_type: string::utf8(POST_TYPE_STANDARD),
            parent_post_id: option::none(),
            mentions,
        });
    }

    /// Internal function to create a comment and return its ID
    fun create_comment_internal(
        post_id: address,
        parent_comment_id: Option<address>,
        owner: address,
        profile_id: address,
        content: String,
        media_option: Option<vector<Url>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        ctx: &mut TxContext
    ): address {
        // Create the comment
        let comment = Comment {
            id: object::new(ctx),
            post_id,
            parent_comment_id,  // Either none or some parent comment ID
            owner,
            profile_id,
            content,
            media: media_option,
            mentions,
            metadata_json,
            created_at: tx_context::epoch(ctx),
            reaction_count: 0,
            comment_count: 0,
            repost_count: 0,
            tips_received: 0,
            removed_from_platform: false,
            user_reactions: table::new(ctx),
            reaction_counts: table::new(ctx),
        };
        
        // Get comment ID before sharing
        let comment_id = object::uid_to_address(&comment.id);
        
        // Share object
        transfer::share_object(comment);
        
        // Return the comment ID
        comment_id
    }

    /// Create a comment - unified function for standard comments and nested comments
    public entry fun create_comment(
        registry: &UsernameRegistry,
        post: &mut Post,
        parent_comment_id: Option<address>, // Optional: if present, creates a nested comment
        content: String,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        ctx: &mut TxContext
    ) {
        // Get sender information
        let owner = tx_context::sender(ctx);
        
        // Look up the profile ID for the sender
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let profile_id = option::extract(&mut profile_id_option);
        
        // Get post ID
        let post_id = object::uid_to_address(&post.id);
        
        // Validate content length
        assert!(string::length(&content) <= MAX_CONTENT_LENGTH, EContentTooLarge);
        
        // Validate metadata size if provided
        if (option::is_some(&metadata_json)) {
            let metadata_ref = option::borrow(&metadata_json);
            assert!(string::length(metadata_ref) <= MAX_METADATA_SIZE, EContentTooLarge);
        };
        
        // Convert and validate media URLs if provided
        let media_option = if (option::is_some(&media_urls)) {
            let urls_bytes = option::extract(&mut media_urls);
            
            // Validate media URLs count
            assert!(vector::length(&urls_bytes) <= MAX_MEDIA_URLS, ETooManyMediaUrls);
            
            // Convert media URL bytes to Url
            let mut urls = vector::empty<Url>();
            let mut i = 0;
            let len = vector::length(&urls_bytes);
            while (i < len) {
                let url_bytes = *vector::borrow(&urls_bytes, i);
                vector::push_back(&mut urls, url::new_unsafe_from_bytes(url_bytes));
                i = i + 1;
            };
            option::some(urls)
        } else {
            option::none<vector<Url>>()
        };
        
        // Validate mentions if provided
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= MAX_MENTIONS, EContentTooLarge);
        };
        
        // Create and share the comment
        let comment_id = create_comment_internal(
            post_id,
            parent_comment_id,
            owner,
            profile_id,
            content,
            media_option,
            mentions,
            metadata_json,
            ctx
        );
        
        // Increment post comment count
        post.comment_count = post.comment_count + 1;
        
        // Emit comment created event
        event::emit(CommentCreatedEvent {
            comment_id,
            post_id,
            parent_comment_id,
            owner,
            profile_id,
            content,
            mentions,
        });
    }

    /// Create a repost or quote repost depending on provided parameters
    /// If content is provided, it's treated as a quote repost
    /// If content is empty/none, it's treated as a standard repost
    public entry fun create_repost(
        registry: &UsernameRegistry,
        original_post: &mut Post,
        mut content: Option<String>,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        
        // Look up the profile ID for the sender (for reference, not ownership)
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let profile_id = option::extract(&mut profile_id_option);
        
        let original_post_id = object::uid_to_address(&original_post.id);
        
        // Determine if this is a quote repost or standard repost
        let is_quote_repost = option::is_some(&content) && string::length(option::borrow(&content)) > 0;
        
        // Initialize content string
        let content_string = if (is_quote_repost) {
            // Validate content length for quote reposts
            let content_value = option::extract(&mut content);
            assert!(string::length(&content_value) <= MAX_CONTENT_LENGTH, EContentTooLarge);
            content_value
        } else {
            // Empty string for standard reposts
            string::utf8(b"")
        };
        
        // Validate and process media URLs if provided
        let media_option = if (option::is_some(&media_urls)) {
            let urls_bytes = option::extract(&mut media_urls);
            
            // Validate media URLs count
            assert!(vector::length(&urls_bytes) <= MAX_MEDIA_URLS, ETooManyMediaUrls);
            
            // Convert media URL bytes to Url
            let mut urls = vector::empty<Url>();
            let mut i = 0;
            let len = vector::length(&urls_bytes);
            while (i < len) {
                let url_bytes = *vector::borrow(&urls_bytes, i);
                vector::push_back(&mut urls, url::new_unsafe_from_bytes(url_bytes));
                i = i + 1;
            };
            option::some(urls)
        } else {
            option::none<vector<Url>>()
        };
        
        // Validate metadata size if provided
        if (option::is_some(&metadata_json)) {
            let metadata_ref = option::borrow(&metadata_json);
            assert!(string::length(metadata_ref) <= MAX_METADATA_SIZE, EContentTooLarge);
        };
        
        // Validate mentions if provided
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= MAX_MENTIONS, EContentTooLarge);
        };
        
        // Create repost as post with appropriate type
        let post_type = if (is_quote_repost) {
            string::utf8(POST_TYPE_QUOTE_REPOST)
        } else {
            string::utf8(POST_TYPE_REPOST)
        };
        
        // For standard reposts, also create a Repost object
        if (!is_quote_repost) {
            let repost = Repost {
                id: object::new(ctx),
                original_id: original_post_id,
                is_original_post: true,
                owner,
                profile_id,
                created_at: tx_context::epoch(ctx),
            };
            
            // Get repost ID before sharing
            let repost_id = object::uid_to_address(&repost.id);
            
            // Emit repost event before sharing
            event::emit(RepostEvent {
                repost_id,
                original_id: original_post_id,
                is_original_post: true,
                owner,
                profile_id,
            });
            
            // Share repost object
            transfer::share_object(repost);
        };
        
        // Increment original post repost count
        original_post.repost_count = original_post.repost_count + 1;
        
        // Create and share the repost post
        let repost_post_id = create_post_internal(
            owner,
            profile_id,
            content_string,
            media_option,
            mentions,
            metadata_json,
            post_type,
            option::some(original_post_id),
            ctx
        );
        
        // Emit post created event for the repost
        event::emit(PostCreatedEvent {
            post_id: repost_post_id,
            owner,
            profile_id,
            content: content_string,
            post_type,
            parent_post_id: option::some(original_post_id),
            mentions,
        });
    }

    /// Delete a post owned by the caller
    public entry fun delete_post(
        post: Post,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == post.owner, EUnauthorized);
        
        // Emit event for the post deletion
        event::emit(PostDeletedEvent {
            post_id: object::uid_to_address(&post.id),
            owner: post.owner,
            profile_id: post.profile_id,
            post_type: post.post_type,
            deleted_at: tx_context::epoch(ctx)
        });
        
        // Extract UID to delete the post object
        let Post {
            id,
            owner: _,
            profile_id: _,
            content: _,
            media: _,
            mentions: _,
            metadata_json: _,
            post_type: _,
            parent_post_id: _,
            created_at: _,
            reaction_count: _,
            comment_count: _,
            repost_count: _,
            tips_received: _,
            removed_from_platform: _,
            user_reactions,
            reaction_counts,
        } = post;
        
        // Clean up associated data structures
        table::drop(user_reactions);
        table::drop(reaction_counts);
        
        // Delete the post object
        object::delete(id);
    }
    
    /// Delete a comment owned by the caller
    public entry fun delete_comment(
        post: &mut Post,
        comment: Comment,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == comment.owner, EUnauthorized);
        
        // Verify the comment belongs to this post
        let comment_post_id = comment.post_id;
        let post_id = object::uid_to_address(&post.id);
        assert!(comment_post_id == post_id, EPostNotFound);
        
        // Decrement the post's comment count
        post.comment_count = post.comment_count - 1;
        
        // Emit event for the comment deletion
        event::emit(CommentDeletedEvent {
            comment_id: object::uid_to_address(&comment.id),
            post_id,
            owner: comment.owner,
            profile_id: comment.profile_id,
            deleted_at: tx_context::epoch(ctx)
        });
        
        // Extract UID to delete the comment object
        let Comment {
            id,
            post_id: _,
            parent_comment_id: _,
            owner: _,
            profile_id: _,
            content: _,
            media: _,
            mentions: _,
            metadata_json: _,
            created_at: _,
            reaction_count: _,
            comment_count: _,
            repost_count: _,
            tips_received: _,
            removed_from_platform: _,
            user_reactions,
            reaction_counts,
        } = comment;
        
        // Clean up associated data structures
        table::drop(user_reactions);
        table::drop(reaction_counts);
        
        // Delete the comment object
        object::delete(id);
    }

    /// React to a post with a specific reaction (emoji or text)
    /// If the user already has the exact same reaction, it will be removed (toggle behavior)
    public entry fun react_to_post(
        post: &mut Post,
        reaction: String,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        
        // Validate reaction length
        assert!(string::length(&reaction) <= MAX_REACTION_LENGTH, EReactionContentTooLong);
        
        // Check if user already reacted to the post
        if (table::contains(&post.user_reactions, user)) {
            // Get the previous reaction
            let previous_reaction = *table::borrow(&post.user_reactions, user);
            
            // If the reaction is the same, remove it (toggle behavior)
            if (reaction == previous_reaction) {
                // Remove user's reaction
                table::remove(&mut post.user_reactions, user);
                
                // Decrease count for this reaction type
                let count = *table::borrow(&post.reaction_counts, reaction);
                if (count <= 1) {
                    table::remove(&mut post.reaction_counts, reaction);
                } else {
                    *table::borrow_mut(&mut post.reaction_counts, reaction) = count - 1;
                };
                
                // Decrement post reaction count
                post.reaction_count = post.reaction_count - 1;
                
                // Emit remove reaction event
                event::emit(RemoveReactionEvent {
                    object_id: object::uid_to_address(&post.id),
                    user,
                    reaction,
                    is_post: true,
                });
                
                return
            };
            
            // Different reaction, update existing one
            // Decrease count for previous reaction
            let previous_count = *table::borrow(&post.reaction_counts, previous_reaction);
            if (previous_count <= 1) {
                table::remove(&mut post.reaction_counts, previous_reaction);
            } else {
                *table::borrow_mut(&mut post.reaction_counts, previous_reaction) = previous_count - 1;
            };
            
            // Update user's reaction
            *table::borrow_mut(&mut post.user_reactions, user) = reaction;
        } else {
            // New reaction from this user
            table::add(&mut post.user_reactions, user, reaction);
            
            // Increment post reaction count
            post.reaction_count = post.reaction_count + 1;
        };
        
        // Increment count for the reaction
        if (table::contains(&post.reaction_counts, reaction)) {
            let count = *table::borrow(&post.reaction_counts, reaction);
            *table::borrow_mut(&mut post.reaction_counts, reaction) = count + 1;
        } else {
            table::add(&mut post.reaction_counts, reaction, 1);
        };
        
        // Emit reaction event
        event::emit(ReactionEvent {
            object_id: object::uid_to_address(&post.id),
            user,
            reaction,
            is_post: true,
        });
    }

    /// Tip a post with MYS tokens (standard post)
    public entry fun tip_post(
        post: &mut Post,
        coin: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let tipper = tx_context::sender(ctx);
        
        // Check if amount is valid
        assert!(amount > 0 && coin::value(coin) >= amount, EInvalidTipAmount);
        
        // Prevent self-tipping
        assert!(tipper != post.owner, ESelfTipping);
        
        // Verify this is not a repost or quote repost (those should use tip_repost instead)
        assert!(
            string::utf8(POST_TYPE_REPOST) != post.post_type && 
            string::utf8(POST_TYPE_QUOTE_REPOST) != post.post_type,
            EInvalidPostType
        );
        
        // Extract tip amount from tipper's coin
        let tip_coin = coin::split(coin, amount, ctx);
        
        // Increment the tip counter for tracking purposes
        post.tips_received = post.tips_received + amount;
        
        // Transfer tip directly to post owner
        transfer::public_transfer(tip_coin, post.owner);
        
        // Emit tip event
        event::emit(TipEvent {
            tipper,
            recipient: post.owner,
            object_id: object::uid_to_address(&post.id),
            amount,
            is_post: true,
        });
    }
    
    /// Tip a repost with MYS tokens - applies 50/50 split between repost owner and original post owner
    public entry fun tip_repost(
        post: &mut Post, // The repost
        original_post: &mut Post, // The original post
        coin: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let tipper = tx_context::sender(ctx);
        
        // Check if amount is valid
        assert!(amount > 0 && coin::value(coin) >= amount, EInvalidTipAmount);
        
        // Prevent self-tipping
        assert!(tipper != post.owner, ESelfTipping);
        
        // Verify this is a repost or quote repost
        assert!(
            string::utf8(POST_TYPE_REPOST) == post.post_type || 
            string::utf8(POST_TYPE_QUOTE_REPOST) == post.post_type,
            EInvalidPostType
        );
        
        // Verify the post has a parent_post_id
        assert!(option::is_some(&post.parent_post_id), EInvalidParentReference);
        
        // Verify the original_post ID matches the parent_post_id
        let parent_id = *option::borrow(&post.parent_post_id);
        assert!(parent_id == object::uid_to_address(&original_post.id), EInvalidParentReference);
        
        // Skip split if repost owner and original post owner are the same
        if (post.owner == original_post.owner) {
            // Standard flow - all goes to the same owner
            let tip_coin = coin::split(coin, amount, ctx);
            post.tips_received = post.tips_received + amount;
            transfer::public_transfer(tip_coin, post.owner);
            
            // Emit tip event
            event::emit(TipEvent {
                tipper,
                recipient: post.owner,
                object_id: object::uid_to_address(&post.id),
                amount,
                is_post: true,
            });
        } else {
            // Calculate split - 50/50 between repost owner and original post owner
            let repost_owner_amount = (amount * REPOST_TIP_PERCENTAGE) / 100;
            let original_owner_amount = amount - repost_owner_amount;
            
            // Extract and split coins
            let mut tip_coin = coin::split(coin, amount, ctx);
            let original_owner_coin = coin::split(&mut tip_coin, original_owner_amount, ctx);
            
            // Increment the tip counters for tracking purposes
            post.tips_received = post.tips_received + repost_owner_amount;
            original_post.tips_received = original_post.tips_received + original_owner_amount;
            
            // Transfer the repost owner's share
            transfer::public_transfer(tip_coin, post.owner);
            
            // Transfer the original post owner's share
            transfer::public_transfer(original_owner_coin, original_post.owner);
            
            // Emit tip event for the repost owner
            event::emit(TipEvent {
                tipper,
                recipient: post.owner,
                object_id: object::uid_to_address(&post.id),
                amount: repost_owner_amount,
                is_post: true,
            });
            
            // Emit tip event for the original post owner
            event::emit(TipEvent {
                tipper, 
                recipient: original_post.owner,
                object_id: object::uid_to_address(&original_post.id),
                amount: original_owner_amount,
                is_post: true,
            });
        }
    }

    /// Tip a comment with MYS tokens
    /// Split is 80% to commenter, 20% to post owner
    public entry fun tip_comment(
        comment: &mut Comment,
        post: &mut Post,
        coin: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let tipper = tx_context::sender(ctx);
        
        // Check if amount is valid
        assert!(amount > 0 && coin::value(coin) >= amount, EInvalidTipAmount);
        
        // Prevent self-tipping
        assert!(tipper != comment.owner, ESelfTipping);
        
        // Extract tip amount from tipper's coin
        let mut tip_coin = coin::split(coin, amount, ctx);
        
        // Calculate split based on constant percentage
        let commenter_amount = (amount * COMMENTER_TIP_PERCENTAGE) / 100;
        let post_owner_amount = amount - commenter_amount;
        
        // Split the tip
        let post_owner_coin = coin::split(&mut tip_coin, post_owner_amount, ctx);
        
        // Increment the tip counters for tracking purposes
        comment.tips_received = comment.tips_received + commenter_amount;
        post.tips_received = post.tips_received + post_owner_amount;
        
        // Transfer the commenter's share 
        transfer::public_transfer(tip_coin, comment.owner);
        
        // Transfer the post owner's share
        transfer::public_transfer(post_owner_coin, post.owner);
        
        // Emit tip event
        event::emit(TipEvent {
            tipper,
            recipient: comment.owner,
            object_id: object::uid_to_address(&comment.id),
            amount,
            is_post: false,
        });
    }

    /// Transfer post ownership to another user (by post owner)
    public entry fun transfer_post_ownership(
        post: &mut Post,
        new_owner: address,
        registry: &UsernameRegistry,
        ctx: &mut TxContext
    ) {
        let current_owner = tx_context::sender(ctx);
        
        // Verify current owner is authorized
        assert!(current_owner == post.owner, EUnauthorizedTransfer);
        
        // Look up the profile ID for the new owner (for reference, not ownership)
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, new_owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let new_profile_id = option::extract(&mut profile_id_option);
        
        // Update post ownership
        let previous_owner = post.owner;
        post.owner = new_owner;
        post.profile_id = new_profile_id;
        
        // Emit ownership transfer event
        event::emit(OwnershipTransferEvent {
            object_id: object::uid_to_address(&post.id),
            previous_owner,
            new_owner,
            is_post: true,
        });
    }

    /// Admin function to transfer post ownership (requires Publisher)
    public entry fun admin_transfer_post_ownership(
        publisher: &Publisher,
        post: &mut Post,
        new_owner: address,
        registry: &UsernameRegistry,
        ctx: &mut TxContext
    ) {
        // Verify the publisher is for this module
        assert!(package::from_module<Post>(publisher), EUnauthorizedTransfer);
        
        // Look up the profile ID for the new owner (for reference, not ownership)
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, new_owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let new_profile_id = option::extract(&mut profile_id_option);
        
        // Update post ownership
        let previous_owner = post.owner;
        post.owner = new_owner;
        post.profile_id = new_profile_id;
        
        // Emit ownership transfer event
        event::emit(OwnershipTransferEvent {
            object_id: object::uid_to_address(&post.id),
            previous_owner,
            new_owner,
            is_post: true,
        });
    }

    /// Moderate a post (remove/restore from platform)
    public entry fun moderate_post(
        post: &mut Post,
        platform: &platform::Platform,
        remove: bool,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform developer or moderator
        let caller = tx_context::sender(ctx);
        assert!(platform::is_developer_or_moderator(platform, caller), EUnauthorized);
        
        // Update post status
        post.removed_from_platform = remove;
        
        // Emit moderation event
        event::emit(PostModerationEvent {
            post_id: object::uid_to_address(&post.id),
            platform_id: object::uid_to_address(platform::id(platform)),
            removed: remove,
            moderated_by: caller,
        });
    }

    /// Moderate a comment (remove/restore from platform)
    public entry fun moderate_comment(
        comment: &mut Comment,
        platform: &platform::Platform,
        remove: bool,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform developer or moderator
        let caller = tx_context::sender(ctx);
        assert!(platform::is_developer_or_moderator(platform, caller), EUnauthorized);
        
        // Update comment status
        comment.removed_from_platform = remove;
        
        // Emit moderation event
        event::emit(PostModerationEvent {
            post_id: object::uid_to_address(&comment.id),
            platform_id: object::uid_to_address(platform::id(platform)),
            removed: remove,
            moderated_by: caller,
        });
    }

    /// Update an existing post
    public entry fun update_post(
        post: &mut Post,
        content: String,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        ctx: &mut TxContext
    ) {
        // Verify caller is the owner
        let owner = tx_context::sender(ctx);
        assert!(owner == post.owner, EUnauthorized);
        
        // Validate content length
        assert!(string::length(&content) <= MAX_CONTENT_LENGTH, EContentTooLarge);
        
        // Validate and update metadata if provided
        if (option::is_some(&metadata_json)) {
            let metadata_string = option::borrow(& metadata_json);
            assert!(string::length(metadata_string) <= MAX_METADATA_SIZE, EContentTooLarge);
            // Clear the current value and set the new one
            post.metadata_json = option::some(*metadata_string);
        };
        
        // Convert and validate media URLs if provided
        if (option::is_some(&media_urls)) {
            let urls_bytes = option::extract(&mut media_urls);
            
            // Validate media URLs count
            assert!(vector::length(&urls_bytes) <= MAX_MEDIA_URLS, ETooManyMediaUrls);
            
            // Convert media URL bytes to Url
            let mut urls = vector::empty<Url>();
            let mut i = 0;
            let len = vector::length(&urls_bytes);
            while (i < len) {
                let url_bytes = *vector::borrow(&urls_bytes, i);
                vector::push_back(&mut urls, url::new_unsafe_from_bytes(url_bytes));
                i = i + 1;
            };
            post.media = option::some(urls);
        };
        
        // Validate mentions if provided
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= MAX_MENTIONS, EContentTooLarge);
            post.mentions = mentions;
        };
        
        // Update post content
        post.content = content;
        
        // Emit post updated event
        event::emit(PostUpdatedEvent {
            post_id: object::uid_to_address(&post.id),
            owner: post.owner,
            profile_id: post.profile_id,
            content: post.content,
            metadata_json: post.metadata_json,
            updated_at: tx_context::epoch(ctx),
        });
    }

    /// Update an existing comment
    public entry fun update_comment(
        comment: &mut Comment,
        content: String,
        mentions: Option<vector<address>>,
        ctx: &mut TxContext
    ) {
        // Verify caller is the owner
        let owner = tx_context::sender(ctx);
        assert!(owner == comment.owner, EUnauthorized);
        
        // Validate content length
        assert!(string::length(&content) <= MAX_CONTENT_LENGTH, EContentTooLarge);
        
        // Validate mentions if provided
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= MAX_MENTIONS, EContentTooLarge);
            comment.mentions = mentions;
        };
        
        // Update comment content
        comment.content = content;
        
        // Emit comment updated event
        event::emit(CommentUpdatedEvent {
            comment_id: object::uid_to_address(&comment.id),
            post_id: comment.post_id,
            owner: comment.owner,
            profile_id: comment.profile_id,
            content: comment.content,
            updated_at: tx_context::epoch(ctx),
        });
    }

    /// Report a post
    public entry fun report_post(
        post: &Post,
        reason_code: u8,
        description: String,
        ctx: &mut TxContext
    ) {
        // Validate reason code
        assert!(
            reason_code == REPORT_REASON_SPAM ||
            reason_code == REPORT_REASON_OFFENSIVE ||
            reason_code == REPORT_REASON_MISINFORMATION ||
            reason_code == REPORT_REASON_ILLEGAL ||
            reason_code == REPORT_REASON_IMPERSONATION ||
            reason_code == REPORT_REASON_HARASSMENT ||
            reason_code == REPORT_REASON_OTHER,
            EReportReasonInvalid
        );
        
        // Validate description length
        assert!(string::length(&description) <= MAX_DESCRIPTION_LENGTH, EReportDescriptionTooLong);
        
        // Get reporter's address
        let reporter = tx_context::sender(ctx);
        
        // Emit post reported event
        event::emit(PostReportedEvent {
            post_id: object::uid_to_address(&post.id),
            reporter,
            reason_code,
            description,
            reported_at: tx_context::epoch(ctx),
        });
    }

    /// Report a comment
    public entry fun report_comment(
        comment: &Comment,
        reason_code: u8,
        description: String,
        ctx: &mut TxContext
    ) {
        // Validate reason code
        assert!(
            reason_code == REPORT_REASON_SPAM ||
            reason_code == REPORT_REASON_OFFENSIVE ||
            reason_code == REPORT_REASON_MISINFORMATION ||
            reason_code == REPORT_REASON_ILLEGAL ||
            reason_code == REPORT_REASON_IMPERSONATION ||
            reason_code == REPORT_REASON_HARASSMENT ||
            reason_code == REPORT_REASON_OTHER,
            EReportReasonInvalid
        );
        
        // Validate description length
        assert!(string::length(&description) <= MAX_DESCRIPTION_LENGTH, EReportDescriptionTooLong);
        
        // Get reporter's address
        let reporter = tx_context::sender(ctx);
        
        // Emit comment reported event
        event::emit(CommentReportedEvent {
            comment_id: object::uid_to_address(&comment.id),
            reporter,
            reason_code,
            description,
            reported_at: tx_context::epoch(ctx),
        });
    }

    /// React to a comment with a specific reaction (emoji or text)
    /// If the user already has the exact same reaction, it will be removed (toggle behavior)
    public entry fun react_to_comment(
        comment: &mut Comment,
        reaction: String,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        
        // Validate reaction length
        assert!(string::length(&reaction) <= MAX_REACTION_LENGTH, EReactionContentTooLong);
        
        // Check if user already reacted to the comment
        if (table::contains(&comment.user_reactions, user)) {
            // Get the previous reaction
            let previous_reaction = *table::borrow(&comment.user_reactions, user);
            
            // If the reaction is the same, remove it (toggle behavior)
            if (reaction == previous_reaction) {
                // Remove user's reaction
                table::remove(&mut comment.user_reactions, user);
                
                // Decrease count for this reaction type
                let count = *table::borrow(&comment.reaction_counts, reaction);
                if (count <= 1) {
                    table::remove(&mut comment.reaction_counts, reaction);
                } else {
                    *table::borrow_mut(&mut comment.reaction_counts, reaction) = count - 1;
                };
                
                // Decrement comment reaction count
                comment.reaction_count = comment.reaction_count - 1;
                
                // Emit remove reaction event
                event::emit(RemoveReactionEvent {
                    object_id: object::uid_to_address(&comment.id),
                    user,
                    reaction,
                    is_post: false,
                });
                
                return
            };
            
            // Different reaction, update existing one
            // Decrease count for previous reaction
            let previous_count = *table::borrow(&comment.reaction_counts, previous_reaction);
            if (previous_count <= 1) {
                table::remove(&mut comment.reaction_counts, previous_reaction);
            } else {
                *table::borrow_mut(&mut comment.reaction_counts, previous_reaction) = previous_count - 1;
            };
            
            // Update user's reaction
            *table::borrow_mut(&mut comment.user_reactions, user) = reaction;
        } else {
            // New reaction from this user
            table::add(&mut comment.user_reactions, user, reaction);
            
            // Increment comment reaction count
            comment.reaction_count = comment.reaction_count + 1;
        };
        
        // Increment count for the reaction
        if (table::contains(&comment.reaction_counts, reaction)) {
            let count = *table::borrow(&comment.reaction_counts, reaction);
            *table::borrow_mut(&mut comment.reaction_counts, reaction) = count + 1;
        } else {
            table::add(&mut comment.reaction_counts, reaction, 1);
        };
        
        // Emit reaction event
        event::emit(ReactionEvent {
            object_id: object::uid_to_address(&comment.id),
            user,
            reaction,
            is_post: false,
        });
    }

    /// Get post content
    public fun get_post_content(post: &Post): String {
        post.content
    }

    /// Get post owner
    public fun get_post_owner(post: &Post): address {
        post.owner
    }

    /// Get post ID
    public fun get_post_id(post: &Post): &UID {
        &post.id
    }

    /// Get post comment count
    public fun get_post_comment_count(post: &Post): u64 {
        post.comment_count
    }

    /// Get comment owner
    public fun get_comment_owner(comment: &Comment): address {
        comment.owner
    }

    /// Get comment post ID
    public fun get_comment_post_id(comment: &Comment): address {
        comment.post_id
    }
}