// Copyright (c) MySocial, Inc.
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
    use mys::balance::{Self, Balance};
    use mys::mys::MYS;
    use mys::url::{Self, Url};
    
    use social_contracts::profile::{Self, Profile};
    use social_contracts::reputation;

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EPostNotFound: u64 = 1;
    const EAlreadyLiked: u64 = 2;
    const ENotLiked: u64 = 3;
    const EInvalidTipAmount: u64 = 4;

    /// Post object that contains content information
    public struct Post has key, store {
        id: UID,
        /// Author's profile ID
        author: address,
        /// Post content
        content: String,
        /// Optional media URL
        media: Option<Url>,
        /// Mentioned users (profile IDs)
        mentions: vector<address>,
        /// Creation timestamp
        created_at: u64,
        /// Number of likes
        like_count: u64,
        /// Number of comments
        comment_count: u64,
        /// Tips received in MYS tokens
        tips_received: Balance<MYS>,
    }

    /// Comment object for posts
    public struct Comment has key, store {
        id: UID,
        /// The post this comment belongs to
        post_id: address,
        /// Comment author's profile ID
        author: address,
        /// Comment content
        content: String,
        /// Creation timestamp
        created_at: u64,
        /// Number of likes
        like_count: u64,
        /// Tips received in MYS tokens
        tips_received: Balance<MYS>,
    }

    /// Collection of likes for a post or comment
    public struct Likes has key {
        id: UID,
        /// The object ID that these likes belong to (post or comment)
        object_id: address,
        /// Table of user addresses that liked this post/comment
        users: Table<address, bool>,
    }

    /// Post created event
    public struct PostCreatedEvent has copy, drop {
        post_id: address,
        author: address,
        content: String,
        mentions: vector<address>,
    }

    /// Comment created event
    public struct CommentCreatedEvent has copy, drop {
        comment_id: address,
        post_id: address,
        author: address,
        content: String,
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

    /// Create a new post
    public fun create_post(
        author_profile: &Profile,
        content: String,
        media_url: Option<vector<u8>>,
        mentions: vector<address>,
        ctx: &mut TxContext
    ): Post {
        let author_id = object::uid_to_address(profile::id(author_profile));
        
        // Convert media URL bytes to Url if provided
        let mut media_url_mut = media_url;
        let media = if (option::is_some(&media_url_mut)) {
            let url_bytes = option::extract(&mut media_url_mut);
            option::some(url::new_unsafe_from_bytes(url_bytes))
        } else {
            option::none()
        };
        
        let post = Post {
            id: object::new(ctx),
            author: author_id,
            content,
            media,
            mentions,
            created_at: tx_context::epoch(ctx),
            like_count: 0,
            comment_count: 0,
            tips_received: balance::zero(),
        };
        
        // Initialize likes collection for this post
        let post_id = object::uid_to_address(&post.id);
        let likes = Likes {
            id: object::new(ctx),
            object_id: post_id,
            users: table::new(ctx),
        };
        
        // Share likes object
        transfer::share_object(likes);
        
        // Emit post created event
        event::emit(PostCreatedEvent {
            post_id,
            author: author_id,
            content: post.content,
            mentions: post.mentions,
        });
        
        // Update author's reputation for creating content
        reputation::add_content_points(object::id(author_profile), 5, ctx);
        
        post
    }

    /// Create a new post and transfer to author
    public entry fun create_and_share_post(
        author_profile: &Profile,
        content: String,
        media_url: vector<u8>,
        mentions: vector<address>,
        ctx: &mut TxContext
    ) {
        let media = if (vector::length(&media_url) > 0) {
            option::some(media_url)
        } else {
            option::none()
        };
        
        let post = create_post(
            author_profile,
            content,
            media,
            mentions,
            ctx
        );
        
        // Share post object
        transfer::share_object(post);
    }

    /// Create a comment on a post
    public entry fun create_comment(
        post: &mut Post,
        author_profile: &Profile,
        content: String,
        ctx: &mut TxContext
    ) {
        let author_id = object::uid_to_address(profile::id(author_profile));
        let post_id = object::uid_to_address(&post.id);
        
        let comment = Comment {
            id: object::new(ctx),
            post_id,
            author: author_id,
            content,
            created_at: tx_context::epoch(ctx),
            like_count: 0,
            tips_received: balance::zero(),
        };
        
        // Initialize likes collection for this comment
        let comment_id = object::uid_to_address(&comment.id);
        let likes = Likes {
            id: object::new(ctx),
            object_id: comment_id,
            users: table::new(ctx),
        };
        
        // Increment post comment count
        post.comment_count = post.comment_count + 1;
        
        // Share objects
        transfer::share_object(comment);
        transfer::share_object(likes);
        
        // Emit comment created event
        event::emit(CommentCreatedEvent {
            comment_id,
            post_id,
            author: author_id,
            content,
        });
        
        // Update author's reputation for creating content
        reputation::add_content_points(object::id(author_profile), 2, ctx);
        
        // Update post author's reputation for engagement
        reputation::add_engagement_points(object::id(author_profile), 1, ctx);
    }

    /// Like a post
    public entry fun like_post(
        post: &mut Post,
        likes: &mut Likes,
        user_profile: &Profile,
        ctx: &mut TxContext
    ) {
        let user_id = object::uid_to_address(profile::id(user_profile));
        let post_id = object::uid_to_address(&post.id);
        
        // Verify likes object matches the post
        assert!(likes.object_id == post_id, EPostNotFound);
        
        // Check if user already liked the post
        assert!(!table::contains(&likes.users, user_id), EAlreadyLiked);
        
        // Add user to likes table
        table::add(&mut likes.users, user_id, true);
        
        // Increment post like count
        post.like_count = post.like_count + 1;
        
        // Emit like event
        event::emit(LikeEvent {
            object_id: post_id,
            user: user_id,
            is_post: true,
        });
        
        // Update post author's reputation for receiving engagement
        reputation::add_engagement_points(object::id(user_profile), 1, ctx);
    }

    /// Unlike a post
    public entry fun unlike_post(
        post: &mut Post,
        likes: &mut Likes,
        user_profile: &Profile,
        ctx: &mut TxContext
    ) {
        let user_id = object::uid_to_address(profile::id(user_profile));
        let post_id = object::uid_to_address(&post.id);
        
        // Verify likes object matches the post
        assert!(likes.object_id == post_id, EPostNotFound);
        
        // Check if user liked the post
        assert!(table::contains(&likes.users, user_id), ENotLiked);
        
        // Remove user from likes table
        table::remove(&mut likes.users, user_id);
        
        // Decrement post like count
        post.like_count = post.like_count - 1;
        
        // Emit unlike event
        event::emit(UnlikeEvent {
            object_id: post_id,
            user: user_id,
            is_post: true,
        });
    }

    /// Like a comment
    public entry fun like_comment(
        comment: &mut Comment,
        likes: &mut Likes,
        user_profile: &Profile,
        ctx: &mut TxContext
    ) {
        let user_id = object::uid_to_address(profile::id(user_profile));
        let comment_id = object::uid_to_address(&comment.id);
        
        // Verify likes object matches the comment
        assert!(likes.object_id == comment_id, EPostNotFound);
        
        // Check if user already liked the comment
        assert!(!table::contains(&likes.users, user_id), EAlreadyLiked);
        
        // Add user to likes table
        table::add(&mut likes.users, user_id, true);
        
        // Increment comment like count
        comment.like_count = comment.like_count + 1;
        
        // Emit like event
        event::emit(LikeEvent {
            object_id: comment_id,
            user: user_id,
            is_post: false,
        });
        
        // Update comment author's reputation for receiving engagement
        reputation::add_engagement_points(object::id(user_profile), 1, ctx);
    }

    /// Unlike a comment
    public entry fun unlike_comment(
        comment: &mut Comment,
        likes: &mut Likes,
        user_profile: &Profile,
        ctx: &mut TxContext
    ) {
        let user_id = object::uid_to_address(profile::id(user_profile));
        let comment_id = object::uid_to_address(&comment.id);
        
        // Verify likes object matches the comment
        assert!(likes.object_id == comment_id, EPostNotFound);
        
        // Check if user liked the comment
        assert!(table::contains(&likes.users, user_id), ENotLiked);
        
        // Remove user from likes table
        table::remove(&mut likes.users, user_id);
        
        // Decrement comment like count
        comment.like_count = comment.like_count - 1;
        
        // Emit unlike event
        event::emit(UnlikeEvent {
            object_id: comment_id,
            user: user_id,
            is_post: false,
        });
    }

    /// Tip a post with MYS tokens
    public entry fun tip_post(
        post: &mut Post,
        tipper_profile: &Profile,
        coin: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let tipper_id = object::uid_to_address(profile::id(tipper_profile));
        
        // Check if amount is valid
        assert!(amount > 0 && coin::value(coin) >= amount, EInvalidTipAmount);
        
        // Extract balance from coin
        let tip_balance = coin::split(coin, amount, ctx);
        
        // Add tip to post's tips received
        balance::join(&mut post.tips_received, coin::into_balance(tip_balance));
        
        // Emit tip event
        event::emit(TipEvent {
            tipper: tipper_id,
            recipient: post.author,
            object_id: object::uid_to_address(&post.id),
            amount,
            is_post: true,
        });
        
        // Update reputation for tipper
        reputation::add_tip_points(object::id(tipper_profile), amount, ctx);
    }

    /// Tip a comment with MYS tokens
    public entry fun tip_comment(
        comment: &mut Comment,
        tipper_profile: &Profile,
        coin: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let tipper_id = object::uid_to_address(profile::id(tipper_profile));
        
        // Check if amount is valid
        assert!(amount > 0 && coin::value(coin) >= amount, EInvalidTipAmount);
        
        // Extract balance from coin
        let tip_balance = coin::split(coin, amount, ctx);
        
        // Add tip to comment's tips received
        balance::join(&mut comment.tips_received, coin::into_balance(tip_balance));
        
        // Emit tip event
        event::emit(TipEvent {
            tipper: tipper_id,
            recipient: comment.author,
            object_id: object::uid_to_address(&comment.id),
            amount,
            is_post: false,
        });
        
        // Update reputation for tipper
        reputation::add_tip_points(object::id(tipper_profile), amount, ctx);
    }

    // === Getters ===
    
    /// Get post author
    public fun author(post: &Post): address {
        post.author
    }
    
    /// Get post content
    public fun content(post: &Post): String {
        post.content
    }
    
    /// Get post media URL
    public fun media(post: &Post): &Option<Url> {
        &post.media
    }
    
    /// Get post mentions
    public fun mentions(post: &Post): vector<address> {
        post.mentions
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
    
    /// Get total tips received by a post
    public fun tips_received(post: &Post): u64 {
        balance::value(&post.tips_received)
    }
    
    /// Get comment author
    public fun comment_author(comment: &Comment): address {
        comment.author
    }
    
    /// Get comment content
    public fun comment_content(comment: &Comment): String {
        comment.content
    }
    
    /// Get comment creation timestamp
    public fun comment_created_at(comment: &Comment): u64 {
        comment.created_at
    }
    
    /// Get comment like count
    public fun comment_like_count(comment: &Comment): u64 {
        comment.like_count
    }
    
    /// Get total tips received by a comment
    public fun comment_tips_received(comment: &Comment): u64 {
        balance::value(&comment.tips_received)
    }
    
    /// Check if a user has liked a post or comment
    public fun has_liked(likes: &Likes, user_id: address): bool {
        table::contains(&likes.users, user_id)
    }
}