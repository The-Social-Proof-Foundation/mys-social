// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Post module for the MySocial network
/// Handles creation and management of posts and comments
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
    
    use social_contracts::profile::{Self, Profile, UsernameRegistry};
    use social_contracts::platform;

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EPostNotFound: u64 = 1;
    const EAlreadyLiked: u64 = 2;
    const ENotLiked: u64 = 3;
    const EInvalidTipAmount: u64 = 4;
    const ESelfTipping: u64 = 5;
    const EInvalidParentReference: u64 = 6;
    const EContentTooLarge: u64 = 7;
    const ETooManyMediaUrls: u64 = 8;
    const EInvalidPostType: u64 = 9;
    const EUnauthorizedTransfer: u64 = 10;
    const ECommentNotFound: u64 = 11;
    const EReportReasonInvalid: u64 = 12;
    const EReportDescriptionTooLong: u64 = 13;

    /// Constants for size limits
    const MAX_CONTENT_LENGTH: u64 = 5000; // 5000 chars max for content
    const MAX_MEDIA_URLS: u64 = 10; // Max 10 media URLs per post
    const MAX_MENTIONS: u64 = 50; // Max 50 mentions per post
    const MAX_METADATA_SIZE: u64 = 10000; // 10KB max for metadata
    const MAX_DESCRIPTION_LENGTH: u64 = 500; // 500 chars max for report description
    const COMMENTER_TIP_PERCENTAGE: u64 = 80; // 80% of tip goes to commenter, 20% to post owner

    /// Valid post types
    const POST_TYPE_STANDARD: vector<u8> = b"standard";
    const POST_TYPE_COMMENT: vector<u8> = b"comment";
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
        /// Number of likes
        like_count: u64,
        /// Number of comments
        comment_count: u64,
        /// Number of reposts
        repost_count: u64,
        /// Total tips received in MYS (tracking only, not actual balance)
        tips_received: u64,
        /// Whether the post has been removed from its platform
        removed_from_platform: bool,
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
        /// Number of likes
        like_count: u64,
        /// Number of nested comments
        comment_count: u64,
        /// Number of reposts
        repost_count: u64,
        /// Total tips received in MYS (tracking only, not actual balance)
        tips_received: u64,
        /// Whether the comment has been removed from its platform
        removed_from_platform: bool,
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

    /// Collection of likes for a post or comment
    public struct Likes has key {
        id: UID,
        /// The object ID that these likes belong to (post or comment)
        object_id: address,
        /// Table of user wallet addresses that liked this post/comment
        users: Table<address, bool>,
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

    /// Like event
    public struct LikeEvent has copy, drop {
        object_id: address,
        user: address,
        is_post: bool,
    }

    /// Unlike event
    public struct UnlikeEvent has copy, drop {
        object_id: address,
        user: address,
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
            like_count: 0,
            comment_count: 0,
            repost_count: 0,
            tips_received: 0,
            removed_from_platform: false,
        };
        
        // Get post ID before sharing
        let post_id = object::uid_to_address(&post.id);
        
        // Initialize likes collection for this post
        let likes = Likes {
            id: object::new(ctx),
            object_id: post_id,
            users: table::new(ctx),
        };
        
        // Share objects
        transfer::share_object(likes);
        transfer::share_object(post);
        
        // Return the post ID
        post_id
    }

    /// Create a new post
    public entry fun create_post(
        registry: &social_contracts::profile::UsernameRegistry,
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
            like_count: 0,
            comment_count: 0,
            repost_count: 0,
            tips_received: 0,
            removed_from_platform: false,
        };
        
        // Get comment ID before sharing
        let comment_id = object::uid_to_address(&comment.id);
        
        // Initialize likes collection for this comment
        let likes = Likes {
            id: object::new(ctx),
            object_id: comment_id,
            users: table::new(ctx),
        };
        
        // Share objects
        transfer::share_object(comment);
        transfer::share_object(likes);
        
        // Return the comment ID
        comment_id
    }

    /// Create a comment - unified function for standard comments and nested comments
    public entry fun create_comment(
        registry: &social_contracts::profile::UsernameRegistry,
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
        registry: &social_contracts::profile::UsernameRegistry,
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

    /// Like a post
    public entry fun like_post(
        post: &mut Post,
        likes: &mut Likes,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        let post_id = object::uid_to_address(&post.id);
        
        // Verify likes object matches the post
        assert!(likes.object_id == post_id, EPostNotFound);
        
        // Check if user already liked the post
        assert!(!table::contains(&likes.users, user), EAlreadyLiked);
        
        // Add user to likes table
        table::add(&mut likes.users, user, true);
        
        // Increment post like count
        post.like_count = post.like_count + 1;
        
        // Emit like event
        event::emit(LikeEvent {
            object_id: post_id,
            user,
            is_post: true,
        });
    }

    /// Unlike a post
    public entry fun unlike_post(
        post: &mut Post,
        likes: &mut Likes,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        let post_id = object::uid_to_address(&post.id);
        
        // Verify likes object matches the post
        assert!(likes.object_id == post_id, EPostNotFound);
        
        // Check if user liked the post
        assert!(table::contains(&likes.users, user), ENotLiked);
        
        // Remove user from likes table
        table::remove(&mut likes.users, user);
        
        // Decrement post like count
        post.like_count = post.like_count - 1;
        
        // Emit unlike event
        event::emit(UnlikeEvent {
            object_id: post_id,
            user,
            is_post: true,
        });
    }

    /// Tip a post with MYS tokens
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

    /// Transfer post ownership to another user
    public entry fun transfer_post_ownership(
        post: &mut Post,
        new_owner: address,
        registry: &social_contracts::profile::UsernameRegistry,
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

    /// Like a comment
    public entry fun like_comment(
        comment: &mut Comment,
        likes: &mut Likes,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        let comment_id = object::uid_to_address(&comment.id);
        
        // Verify likes object matches the comment
        assert!(likes.object_id == comment_id, ECommentNotFound);
        
        // Check if user already liked the comment
        assert!(!table::contains(&likes.users, user), EAlreadyLiked);
        
        // Add user to likes table
        table::add(&mut likes.users, user, true);
        
        // Increment comment like count
        comment.like_count = comment.like_count + 1;
        
        // Emit like event
        event::emit(LikeEvent {
            object_id: comment_id,
            user,
            is_post: false,
        });
    }

    /// Unlike a comment
    public entry fun unlike_comment(
        comment: &mut Comment,
        likes: &mut Likes,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        let comment_id = object::uid_to_address(&comment.id);
        
        // Verify likes object matches the comment
        assert!(likes.object_id == comment_id, ECommentNotFound);
        
        // Check if user liked the comment
        assert!(table::contains(&likes.users, user), ENotLiked);
        
        // Remove user from likes table
        table::remove(&mut likes.users, user);
        
        // Decrement comment like count
        comment.like_count = comment.like_count - 1;
        
        // Emit unlike event
        event::emit(UnlikeEvent {
            object_id: comment_id,
            user,
            is_post: false,
        });
    }

    // === Getters ===
    
    /// Get post author (for backward compatibility)
    public fun author(post: &Post): address {
        post.profile_id
    }
    
    /// Get post wallet address (for backward compatibility)
    public fun wallet_address(post: &Post): address {
        post.owner
    }
    
    /// Get post owner address
    public fun owner(post: &Post): address {
        post.owner
    }
    
    /// Get post profile ID
    public fun profile_id(post: &Post): address {
        post.profile_id
    }
    
    /// Get post content
    public fun content(post: &Post): String {
        post.content
    }
    
    /// Get post media URLs
    public fun media(post: &Post): &Option<vector<Url>> {
        &post.media
    }
    
    /// Get post mentions
    public fun mentions(post: &Post): &Option<vector<address>> {
        &post.mentions
    }
    
    /// Get post metadata
    public fun metadata_json(post: &Post): Option<String> {
        // If metadata exists, return a copy, otherwise return none
        if (option::is_some(&post.metadata_json)) {
            option::some(*option::borrow(&post.metadata_json))
        } else {
            option::none()
        }
    }
    
    /// Get post type
    public fun post_type(post: &Post): String {
        post.post_type
    }
    
    /// Get parent post ID if any
    public fun parent_post_id(post: &Post): &Option<address> {
        &post.parent_post_id
    }
    
    /// Get post creation timestamp
    public fun created_at(post: &Post): u64 {
        post.created_at
    }
    
    /// Get post ID
    public fun id(post: &Post): &UID {
        &post.id
    }
    
    /// Get post like count
    public fun like_count(post: &Post): u64 {
        post.like_count
    }
    
    /// Get post comment count
    public fun comment_count(post: &Post): u64 {
        post.comment_count
    }
    
    /// Get post repost count
    public fun repost_count(post: &Post): u64 {
        post.repost_count
    }
    
    /// Get total tips received by a post
    public fun tips_received(post: &Post): u64 {
        post.tips_received
    }
    
    /// Get comment author (for backward compatibility)
    public fun comment_author(comment: &Comment): address {
        comment.profile_id
    }
    
    /// Get comment wallet address (for backward compatibility)
    public fun comment_wallet_address(comment: &Comment): address {
        comment.owner
    }
    
    /// Get comment owner address
    public fun comment_owner(comment: &Comment): address {
        comment.owner
    }
    
    /// Get comment profile ID
    public fun comment_profile_id(comment: &Comment): address {
        comment.profile_id
    }
    
    /// Get comment content
    public fun comment_content(comment: &Comment): String {
        comment.content
    }
    
    /// Get comment media URLs
    public fun comment_media(comment: &Comment): &Option<vector<Url>> {
        &comment.media
    }
    
    /// Get comment mentions
    public fun comment_mentions(comment: &Comment): &Option<vector<address>> {
        &comment.mentions
    }
    
    /// Get comment parent ID if any
    public fun parent_comment_id(comment: &Comment): &Option<address> {
        &comment.parent_comment_id
    }
    
    /// Get comment creation timestamp
    public fun comment_created_at(comment: &Comment): u64 {
        comment.created_at
    }
    
    /// Get comment like count
    public fun comment_like_count(comment: &Comment): u64 {
        comment.like_count
    }
    
    /// Get comment repost count
    public fun comment_repost_count(comment: &Comment): u64 {
        comment.repost_count
    }
    
    /// Get total tips received by a comment
    public fun comment_tips_received(comment: &Comment): u64 {
        comment.tips_received
    }
    
    /// Check if a user has liked a post or comment
    public fun has_liked(likes: &Likes, user: address): bool {
        table::contains(&likes.users, user)
    }

    /// Get comment metadata
    public fun comment_metadata_json(comment: &Comment): Option<String> {
        // If metadata exists, return a copy, otherwise return none
        if (option::is_some(&comment.metadata_json)) {
            option::some(*option::borrow(&comment.metadata_json))
        } else {
            option::none()
        }
    }
}