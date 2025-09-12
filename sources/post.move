// Copyright (c) The Social Proof Foundation, LLC.
// SPDX-License-Identifier: Apache-2.0

/// Post module for the MySocial network
/// Handles creation and management of posts and comments
/// Implements features like comments, reposts, quotes, and predictions

#[allow(duplicate_alias, unused_use, unused_const, unused_variable)]
module social_contracts::post {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    
    use mys::{
        object::{Self, UID, ID},
        tx_context::{Self, TxContext},
        transfer,
        event,
        table::{Self, Table},
        coin::{Self, Coin},
        balance::{Self, Balance},
        url::{Self, Url},
        clock::{Self, Clock}
    };
    use mys::mys::MYS;
    use social_contracts::subscription::{Self, ProfileSubscriptionService, ProfileSubscription};
    use social_contracts::profile::UsernameRegistry;
    use social_contracts::platform;
    use social_contracts::block_list::{Self, BlockListRegistry};
    use social_contracts::upgrade::{Self, UpgradeAdminCap};
    use social_contracts::proof_of_creativity;

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EPostNotFound: u64 = 1;
    const EInvalidTipAmount: u64 = 2;
    const ESelfTipping: u64 = 3;
    const EInvalidParentReference: u64 = 4;
    const EContentTooLarge: u64 = 5;
    const ETooManyMediaUrls: u64 = 6;
    const EInvalidPostType: u64 = 7;
    const EUnauthorizedTransfer: u64 = 8;
    const EReportReasonInvalid: u64 = 9;
    const EReportDescriptionTooLong: u64 = 10;
    const EReactionContentTooLong: u64 = 11;
    const EPredictionOptionsTooMany: u64 = 12;
    const EPredictionOptionsEmpty: u64 = 13;
    const EPredictionAlreadyResolved: u64 = 14;
    const EPredictionOptionInvalid: u64 = 15;
    const ENotPredictionPost: u64 = 16;
    const EPredictionBettingClosed: u64 = 17;
    const EPredictionDisabled: u64 = 18;
    const EUserNotJoinedPlatform: u64 = 19;
    const EUserBlockedByPlatform: u64 = 20;
    const EWrongVersion: u64 = 21;
    const EReactionsNotAllowed: u64 = 22;
    const ECommentsNotAllowed: u64 = 23;
    const ERepostsNotAllowed: u64 = 24;
    const EQuotesNotAllowed: u64 = 25;
    const ETipsNotAllowed: u64 = 26;
    const EInvalidConfig: u64 = 28;
    const ENoSubscriptionService: u64 = 29;
    const ENoEncryptedContent: u64 = 30;
    const EPriceMismatch: u64 = 31;
    const EPromotionAmountTooLow: u64 = 32;
    const EPromotionAmountTooHigh: u64 = 33;
    const ENotPromotedPost: u64 = 34;
    const EUserAlreadyViewed: u64 = 35;
    const EInsufficientPromotionFunds: u64 = 36;
    const EPromotionInactive: u64 = 37;
    const EInvalidViewDuration: u64 = 38;

    /// Constants for size limits
    const MAX_CONTENT_LENGTH: u64 = 5000; // 5000 chars max for content
    const MAX_MEDIA_URLS: u64 = 10; // Max 10 media URLs per post
    const MAX_MENTIONS: u64 = 10; // Max 50 mentions per post
    const MAX_METADATA_SIZE: u64 = 10000; // 10KB max for metadata
    const MAX_DESCRIPTION_LENGTH: u64 = 500; // 500 chars max for report description
    const MAX_REACTION_LENGTH: u64 = 20; // 50 chars max for a reaction
    const COMMENTER_TIP_PERCENTAGE: u64 = 80; // 80% of tip goes to commenter, 20% to post owner
    const REPOST_TIP_PERCENTAGE: u64 = 50; // 50% of tip goes to repost owner, 50% to original post owner
    const MAX_PREDICTION_OPTIONS: u64 = 10; // Maximum number of prediction options
    const MAX_U64: u64 = 18446744073709551615; // Max u64 value for overflow protection
    
    /// Constants for promoted posts
    const MIN_PROMOTION_AMOUNT: u64 = 1000; // Minimum 0.001 MYS (1000 MIST) per view
    const MAX_PROMOTION_AMOUNT: u64 = 100000000; // Maximum 100 MYS per view
    const MIN_VIEW_DURATION: u64 = 3000; // Minimum 3 seconds view time in milliseconds

    /// Valid post types
    const POST_TYPE_STANDARD: vector<u8> = b"standard";
    const POST_TYPE_REPOST: vector<u8> = b"repost";
    const POST_TYPE_QUOTE_REPOST: vector<u8> = b"quote_repost";
    const POST_TYPE_PREDICTION: vector<u8> = b"prediction";

    /// Constants for report reason codes
    const REPORT_REASON_SPAM: u8 = 1;
    const REPORT_REASON_OFFENSIVE: u8 = 2;
    const REPORT_REASON_MISINFORMATION: u8 = 3;
    const REPORT_REASON_ILLEGAL: u8 = 4;
    const REPORT_REASON_IMPERSONATION: u8 = 5;
    const REPORT_REASON_HARASSMENT: u8 = 6;
    const REPORT_REASON_OTHER: u8 = 99;

    /// Constants for moderation states
    const MODERATION_APPROVED: u8 = 1;
    const MODERATION_FLAGGED: u8 = 2;

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
        /// Direct permission toggles for post interactions
        allow_comments: bool,
        allow_reactions: bool,
        allow_reposts: bool,
        allow_quotes: bool,
        allow_tips: bool,
        /// Optional Proof of Creativity badge ID (for original content that passed verification)
        poc_badge_id: Option<ID>,
        /// Optional revenue redirection to original creator (for derivative content)
        revenue_redirect_to: Option<address>,
        /// Optional revenue redirection percentage (0-100)
        revenue_redirect_percentage: Option<u64>,
        /// Reference to the intellectual property license for the post
        my_ip_id: Option<address>,
        /// Optional promotion data ID for promoted posts
        promotion_id: Option<address>,
        /// Opt-out flag to disable auto SPT pool initialization by SPoT
        disable_auto_pool: bool,
        /// Version for upgrades
        version: u64,
    }

    /// Query: per-post opt-out for auto SPT pool init
    public fun is_auto_pool_disabled(post: &Post): bool { post.disable_auto_pool }

    /// Owner-only: set per-post opt-out flag
    public entry fun set_auto_pool_disabled(
        post: &mut Post,
        disabled: bool,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(caller == post.owner, EUnauthorized);
        post.disable_auto_pool = disabled;
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
        /// Version for upgrades
        version: u64,
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
        /// Version for upgrades
        version: u64,
    }

    /// Prediction option structure
    public struct PredictionOption has store, copy, drop {
        id: u8,
        description: String,
        total_bet: u64,  // Total MYS coins bet on this option
    }

    /// Prediction bet record
    public struct PredictionBet has store, copy, drop {
        user: address,
        option_id: u8,
        amount: u64,
        timestamp: u64,
    }

    /// Prediction metadata
    public struct PredictionData has key, store {
        id: UID,
        post_id: address,
        options: vector<PredictionOption>,
        bets: vector<PredictionBet>,
        resolved: bool,
        winning_option_id: Option<u8>,
        betting_end_time: Option<u64>,
        total_bet_amount: u64,
    }

    /// Promoted post view record
    public struct PromotionView has store, copy, drop {
        viewer: address,
        view_duration: u64,
        view_timestamp: u64,
        platform_id: address,
    }

    /// Promoted post metadata
    public struct PromotionData has key, store {
        id: UID,
        post_id: address,
        /// Amount of MYS to pay per view
        payment_per_view: u64,
        /// MYS balance available for payments
        promotion_budget: Balance<MYS>,
        /// Table tracking which users have already been paid for viewing
        paid_viewers: Table<address, bool>,
        /// List of all views for analytics
        views: vector<PromotionView>,
        /// Whether the promotion is currently active
        active: bool,
        /// Promotion creation timestamp
        created_at: u64,
    }

    /// Admin capability for resolving predictions
    public struct PostAdminCap has key, store {
        id: UID,
    }

    /// Global post feature configuration
    public struct PostConfig has key {
        id: UID,
        /// Indicates if prediction posts are enabled
        predictions_enabled: bool,
        /// Prediction platform fee in basis points (100 = 1%)
        prediction_fee_bps: u64,
        /// Treasury address for prediction fees
        prediction_treasury: address,
        /// Maximum character length for post content
        max_content_length: u64,
        /// Maximum number of media URLs per post
        max_media_urls: u64,
        /// Maximum number of mentions in a post
        max_mentions: u64,
        /// Maximum size for post metadata in bytes
        max_metadata_size: u64,
        /// Maximum length for report descriptions
        max_description_length: u64,
        /// Maximum length for reactions
        max_reaction_length: u64,
        /// Percentage of tip that goes to commenter (remainder to post owner)
        commenter_tip_percentage: u64,
        /// Percentage of tip that goes to reposter (remainder to original post owner)
        repost_tip_percentage: u64,
        /// Maximum number of prediction options
        max_prediction_options: u64,
    }

    /// Event emitted when post parameters are updated
    public struct PostParametersUpdatedEvent has copy, drop {
        /// Who performed the update
        updated_by: address,
        /// When the update occurred
        timestamp: u64,
        /// New max content length value
        max_content_length: u64,
        /// New max media URLs value
        max_media_urls: u64, 
        /// New max mentions value
        max_mentions: u64,
        /// New max metadata size value
        max_metadata_size: u64,
        /// New max description length value
        max_description_length: u64,
        /// New max reaction length value
        max_reaction_length: u64,
        /// New commenter tip percentage value
        commenter_tip_percentage: u64,
        /// New repost tip percentage value
        repost_tip_percentage: u64,
        /// New max prediction options value
        max_prediction_options: u64,
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
    #[allow(unused_field)]
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
        object_id: address,
        from: address,
        to: address,
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

    /// Prediction creation event
    public struct PredictionCreatedEvent has copy, drop {
        post_id: address,
        prediction_data_id: address,
        owner: address,
        profile_id: address,
        content: String,
        options: vector<String>,
        betting_end_time: Option<u64>,
    }

    /// Prediction bet placed event
    public struct PredictionBetPlacedEvent has copy, drop {
        post_id: address,
        user: address,
        option_id: u8,
        amount: u64,
    }

    /// Prediction resolved event
    public struct PredictionResolvedEvent has copy, drop {
        post_id: address,
        winning_option_id: u8,
        total_bet_amount: u64,
        winning_amount: u64,
        resolved_by: address,
    }

    /// Prediction payout event
    public struct PredictionPayoutEvent has copy, drop {
        post_id: address,
        user: address,
        amount: u64,
    }

    /// Prediction bet withdrawn event
    public struct PredictionBetWithdrawnEvent has copy, drop {
        post_id: address,
        user: address,
        option_id: u8,
        original_amount: u64,
        withdrawal_amount: u64,
    }

    /// Event emitted when a promoted post is created
    public struct PromotedPostCreatedEvent has copy, drop {
        post_id: address,
        owner: address,
        profile_id: address,
        payment_per_view: u64,
        total_budget: u64,
        created_at: u64,
    }

    /// Event emitted when a promoted post view is confirmed and payment is made
    public struct PromotedPostViewConfirmedEvent has copy, drop {
        post_id: address,
        viewer: address,
        payment_amount: u64,
        view_duration: u64,
        platform_id: address,
        timestamp: u64,
    }

    /// Event emitted when promotion status is toggled
    public struct PromotionStatusToggledEvent has copy, drop {
        post_id: address,
        toggled_by: address,
        new_status: bool,
        timestamp: u64,
    }

    /// Event emitted when promotion funds are withdrawn
    public struct PromotionFundsWithdrawnEvent has copy, drop {
        post_id: address,
        owner: address,
        withdrawn_amount: u64,
        timestamp: u64,
    }

    /// Simple moderation record for tracking moderation decisions
    public struct ModerationRecord has key {
        id: UID,
        post_id: address,
        platform_id: address,
        moderation_state: u8,
        moderator: Option<address>,
        moderation_timestamp: Option<u64>,
        reason: Option<String>,
    }

    /// Bootstrap initialization function - creates the post configuration
    public(package) fun bootstrap_init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);
        
        // Create and share post configuration with proper treasury
        transfer::share_object(
            PostConfig {
                id: object::new(ctx),
                predictions_enabled: false, // Predictions disabled by default
                prediction_fee_bps: 500, // Default 5% fee
                prediction_treasury: admin, // Auto-configured to admin during bootstrap
                max_content_length: MAX_CONTENT_LENGTH,
                max_media_urls: MAX_MEDIA_URLS,
                max_mentions: MAX_MENTIONS,
                max_metadata_size: MAX_METADATA_SIZE,
                max_description_length: MAX_DESCRIPTION_LENGTH,
                max_reaction_length: MAX_REACTION_LENGTH,
                commenter_tip_percentage: COMMENTER_TIP_PERCENTAGE,
                repost_tip_percentage: REPOST_TIP_PERCENTAGE,
                max_prediction_options: MAX_PREDICTION_OPTIONS,
            }
        );
    }
    
    /// Enable or disable prediction functionality (admin only)
    public entry fun set_predictions_enabled(
        _: &PostAdminCap,
        config: &mut PostConfig,
        enabled: bool,
        _ctx: &mut TxContext
    ) {
        // Admin capability verification is handled by type system
        
        // Update configuration
        config.predictions_enabled = enabled;
    }
    
    /// Set prediction fee (admin only)
    public entry fun set_prediction_fee(
        _: &PostAdminCap,
        config: &mut PostConfig,
        fee_bps: u64,
        treasury: address,
        _ctx: &mut TxContext
    ) {
        // Admin capability verification is handled by type system
        
        // Ensure fee is reasonable (max 25%)
        assert!(fee_bps <= 2500, EInvalidTipAmount);
        
        // Update configuration
        config.prediction_fee_bps = fee_bps;
        config.prediction_treasury = treasury;
    }
    
    /// Check if predictions are enabled
    public fun is_predictions_enabled(config: &PostConfig): bool {
        config.predictions_enabled
    }

    /// Create a new prediction post
    public entry fun create_prediction_post(
        config: &PostConfig,
        _admin_cap: &PostAdminCap,
        registry: &UsernameRegistry,
        platform_registry: &platform::PlatformRegistry,
        platform: &platform::Platform,
        block_list_registry: &block_list::BlockListRegistry,
        content: String,
        options: vector<String>,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        betting_end_time: Option<u64>,
        allow_comments: Option<bool>,
        allow_reactions: Option<bool>,
        allow_reposts: Option<bool>,
        allow_quotes: Option<bool>,
        allow_tips: Option<bool>,
        ctx: &mut TxContext
    ) {
        // Verify predictions are enabled
        assert!(config.predictions_enabled, EPredictionDisabled);
        
        let owner = tx_context::sender(ctx);
        
        // Look up the profile ID for the sender
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let profile_id = option::extract(&mut profile_id_option);
        
        // Check if platform is approved
        let platform_id = object::uid_to_address(platform::id(platform));
        assert!(platform::is_approved(platform_registry, platform_id), EUnauthorized);
        
        // Check if user has joined the platform
        let profile_id_obj = object::id_from_address(profile_id);
        assert!(platform::has_joined_platform(platform, profile_id_obj), EUserNotJoinedPlatform);
        
        // Check if the user is blocked by the platform
        let platform_address = object::uid_to_address(platform::id(platform));
        assert!(!block_list::is_blocked(block_list_registry, platform_address, owner), EUserBlockedByPlatform);
        
        // Validate content length
        assert!(string::length(&content) <= config.max_content_length, EContentTooLarge);
        
        // Validate options
        let options_length = vector::length(&options);
        assert!(options_length > 0, EPredictionOptionsEmpty);
        assert!(options_length <= config.max_prediction_options, EPredictionOptionsTooMany);
        
        // Validate metadata size if provided
        if (option::is_some(&metadata_json)) {
            let metadata_ref = option::borrow(&metadata_json);
            assert!(string::length(metadata_ref) <= config.max_metadata_size, EContentTooLarge);
        };
        
        // Convert and validate media URLs if provided
        let media_option = if (option::is_some(&media_urls)) {
            let urls_bytes = option::extract(&mut media_urls);
            
            // Validate media URLs count
            assert!(vector::length(&urls_bytes) <= config.max_media_urls, ETooManyMediaUrls);
            
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
            assert!(vector::length(mentions_ref) <= config.max_mentions, EContentTooLarge);
        };
        
        // Set defaults for optional boolean parameters
        let final_allow_comments = if (option::is_some(&allow_comments)) {
            *option::borrow(&allow_comments)
        } else {
            true // Default to allowing comments
        };
        let final_allow_reactions = if (option::is_some(&allow_reactions)) {
            *option::borrow(&allow_reactions)
        } else {
            true // Default to allowing reactions
        };
        let final_allow_reposts = if (option::is_some(&allow_reposts)) {
            *option::borrow(&allow_reposts)
        } else {
            true // Default to allowing reposts
        };
        let final_allow_quotes = if (option::is_some(&allow_quotes)) {
            *option::borrow(&allow_quotes)
        } else {
            true // Default to allowing quotes
        };
        let final_allow_tips = if (option::is_some(&allow_tips)) {
            *option::borrow(&allow_tips)
        } else {
            true // Default to allowing tips
        };
        
        // Create the post with prediction type
        let post_id = create_post_internal(
            owner,
            profile_id,
            content,
            media_option,
            mentions,
            metadata_json,
            string::utf8(POST_TYPE_PREDICTION),
            option::none(),
            final_allow_comments,
            final_allow_reactions,
            final_allow_reposts,
            final_allow_quotes,
            final_allow_tips,
            option::none(), // poc_badge_id
            option::none(), // revenue_redirect_to
            option::none(), // revenue_redirect_percentage
            option::none(), // my_ip_id
            option::none(), // promotion_id
            ctx
        );
        
        // Create prediction options
        let mut prediction_options = vector::empty<PredictionOption>();
        let mut i = 0;
        let options_len = vector::length(&options);
        
        while (i < options_len) {
            let option_desc = *vector::borrow(&options, i);
            
            let prediction_option = PredictionOption {
                id: (i as u8),
                description: option_desc,
                total_bet: 0
            };
            
            vector::push_back(&mut prediction_options, prediction_option);
            i = i + 1;
        };
        
        // Create prediction data
        let prediction_data = PredictionData {
            id: object::new(ctx),
            post_id,
            options: prediction_options,
            bets: vector::empty(),
            resolved: false,
            winning_option_id: option::none(),
            betting_end_time,
            total_bet_amount: 0,
        };
        
        let prediction_data_id = object::uid_to_address(&prediction_data.id);
        
        // Extract just the descriptions for the event
        let mut option_descriptions = vector::empty<String>();
        i = 0;
        while (i < options_len) {
            let option = *vector::borrow(&prediction_options, i);
            vector::push_back(&mut option_descriptions, option.description);
            i = i + 1;
        };
        
        // Emit prediction created event
        event::emit(PredictionCreatedEvent {
            post_id,
            prediction_data_id,
            owner,
            profile_id,
            content,
            options: option_descriptions,
            betting_end_time,
        });
        
        // Emit standard post created event
        event::emit(PostCreatedEvent {
            post_id,
            owner,
            profile_id,
            content,
            post_type: string::utf8(POST_TYPE_PREDICTION),
            parent_post_id: option::none(),
            mentions,
        });
        
        // Share prediction data
        transfer::share_object(prediction_data);
    }

    /// Place a bet on a prediction post
    public entry fun place_prediction_bet(
        config: &PostConfig,
        post: &Post,
        prediction_data: &mut PredictionData,
        option_id: u8,
        coin: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Verify predictions are enabled
        assert!(config.predictions_enabled, EPredictionDisabled);
        
        let bettor = tx_context::sender(ctx);
        
        // Verify this is a prediction post
        assert!(string::utf8(POST_TYPE_PREDICTION) == post.post_type, ENotPredictionPost);
        
        // Verify post_id matches
        assert!(object::uid_to_address(&post.id) == prediction_data.post_id, EInvalidParentReference);
        
        // Verify prediction is not resolved yet
        assert!(!prediction_data.resolved, EPredictionAlreadyResolved);
        
        // Check if betting period has ended
        if (option::is_some(&prediction_data.betting_end_time)) {
            let end_time = *option::borrow(&prediction_data.betting_end_time);
            assert!(tx_context::epoch(ctx) <= end_time, EPredictionBettingClosed);
        };
        
        // Verify option_id is valid
        let mut option_valid = false;
        let mut option_index = 0;
        let options_len = vector::length(&prediction_data.options);
        
        while (option_index < options_len) {
            let option = vector::borrow_mut(&mut prediction_data.options, option_index);
            if (option.id == option_id) {
                option_valid = true;
                
                // Update total bet for this option
                option.total_bet = option.total_bet + amount;
                break
            };
            option_index = option_index + 1;
        };
        
        assert!(option_valid, EPredictionOptionInvalid);
        
        // Take bet amount from user's coin
        let bet_coin = coin::split(coin, amount, ctx);
        
        // Transfer bet to post owner (held until resolution)
        transfer::public_transfer(bet_coin, post.owner);
        
        // Record bet
        let bet = PredictionBet {
            user: bettor,
            option_id,
            amount,
            timestamp: tx_context::epoch(ctx),
        };
        
        // Add bet to prediction data
        vector::push_back(&mut prediction_data.bets, bet);
        
        // Update total bet amount
        prediction_data.total_bet_amount = prediction_data.total_bet_amount + amount;
        
        // Emit bet placed event
        event::emit(PredictionBetPlacedEvent {
            post_id: prediction_data.post_id,
            user: bettor,
            option_id,
            amount,
        });
    }

    /// Withdraw a prediction bet with adjusted returns based on current odds
    public entry fun withdraw_prediction_bet(
        config: &PostConfig,
        post: &Post,
        prediction_data: &mut PredictionData,
        repayment_coin: &mut Coin<MYS>,
        ctx: &mut TxContext
    ) {
        // Verify predictions are enabled
        assert!(config.predictions_enabled, EPredictionDisabled);
        
        let withdrawer = tx_context::sender(ctx);
        
        // Verify this is a prediction post
        assert!(string::utf8(POST_TYPE_PREDICTION) == post.post_type, ENotPredictionPost);
        
        // Verify post_id matches
        assert!(object::uid_to_address(&post.id) == prediction_data.post_id, EInvalidParentReference);
        
        // Verify prediction is not resolved yet
        assert!(!prediction_data.resolved, EPredictionAlreadyResolved);
        
        // Check if betting period has ended
        if (option::is_some(&prediction_data.betting_end_time)) {
            let end_time = *option::borrow(&prediction_data.betting_end_time);
            assert!(tx_context::epoch(ctx) <= end_time, EPredictionBettingClosed);
        };
        
        // Find the user's bet
        let bets_len = vector::length(&prediction_data.bets);
        let mut bet_index = 0;
        let mut found_bet = false;
        let mut user_bet_amount = 0;
        let mut user_option_id = 0;
        
        while (bet_index < bets_len) {
            let bet = vector::borrow(&prediction_data.bets, bet_index);
            if (bet.user == withdrawer) {
                user_bet_amount = bet.amount;
                user_option_id = bet.option_id;
                found_bet = true;
                break
            };
            bet_index = bet_index + 1;
        };
        
        // Ensure the user has a bet to withdraw
        assert!(found_bet, EUnauthorized);
        
        // Calculate the current odds and determine the fair withdrawal amount
        
        // Get the total amount bet across all options
        let total_bet_amount = prediction_data.total_bet_amount;
        
        // Get current amount betting settings
        let options_len = vector::length(&prediction_data.options);
        let mut option_index = 0;
        
        while (option_index < options_len) {
            let option = vector::borrow(&prediction_data.options, option_index);
            if (option.id == user_option_id) {
                break
            };
            option_index = option_index + 1;
        };
        
        // Calculate the fair withdrawal amount based on current odds
        // Formula: withdrawal_amount = user_bet_amount * (total_bet_amount - user_bet_amount) / (total_bet_amount)
        
        // Remove the user's bet from the calculation to get actual current market
        let adjusted_total_bet = total_bet_amount - user_bet_amount;
        
        // Calculate the withdrawal amount (using proportion of current odds)
        let mut withdrawal_amount = user_bet_amount;
        
        // Only adjust if there are other bets in the market
        if (adjusted_total_bet > 0) {
            // Calculate fair value based on current odds
            // This formula ensures users get less if odds worsened, more if odds improved
            withdrawal_amount = (((user_bet_amount as u128) * (adjusted_total_bet as u128)) / 
                (adjusted_total_bet as u128)) as u64;
        };
        
        // Ensure there's enough balance in the repayment coin
        assert!(coin::value(repayment_coin) >= withdrawal_amount, EInvalidTipAmount);
        
        // Update prediction data
        // 1. Decrease the total bet amount
        prediction_data.total_bet_amount = prediction_data.total_bet_amount - user_bet_amount;
        
        // 2. Decrease the option's total bet amount
        option_index = 0;
        while (option_index < options_len) {
            let option = vector::borrow_mut(&mut prediction_data.options, option_index);
            if (option.id == user_option_id) {
                option.total_bet = option.total_bet - user_bet_amount;
                break
            };
            option_index = option_index + 1;
        };
        
        // 3. Remove the bet from the vector
        if (bet_index < bets_len - 1) {
            // If not the last element, swap with last and pop
            vector::swap(&mut prediction_data.bets, bet_index, bets_len - 1);
        };
        vector::pop_back(&mut prediction_data.bets);
        
        // Transfer the withdrawal amount to the user
        let withdrawal_coin = coin::split(repayment_coin, withdrawal_amount, ctx);
        transfer::public_transfer(withdrawal_coin, withdrawer);
        
        // Emit prediction bet withdrawn event
        event::emit(PredictionBetWithdrawnEvent {
            post_id: prediction_data.post_id,
            user: withdrawer,
            option_id: user_option_id,
            original_amount: user_bet_amount,
            withdrawal_amount,
        });
    }

    /// Resolve a prediction (admin only) and distribute winnings
    public entry fun resolve_prediction(
        config: &PostConfig,
        _admin_cap: &PostAdminCap,
        post: &Post,
        prediction_data: &mut PredictionData,
        winning_option_id: u8,
        payout_funds: &mut Coin<MYS>,
        ctx: &mut TxContext
    ) {
        // Verify predictions are enabled
        assert!(config.predictions_enabled, EPredictionDisabled);
        
        // Verify this is a prediction post
        assert!(string::utf8(POST_TYPE_PREDICTION) == post.post_type, ENotPredictionPost);
        
        // Verify post_id matches
        assert!(object::uid_to_address(&post.id) == prediction_data.post_id, EInvalidParentReference);
        
        // Verify prediction is not already resolved
        assert!(!prediction_data.resolved, EPredictionAlreadyResolved);
        
        // Verify option_id is valid
        let mut option_valid = false;
        let mut option_index = 0;
        let options_len = vector::length(&prediction_data.options);
        let mut winning_amount = 0;
        
        while (option_index < options_len) {
            let option = vector::borrow(&prediction_data.options, option_index);
            if (option.id == winning_option_id) {
                option_valid = true;
                winning_amount = option.total_bet;
                break
            };
            option_index = option_index + 1;
        };
        
        assert!(option_valid, EPredictionOptionInvalid);
        
        // Mark prediction as resolved
        prediction_data.resolved = true;
        prediction_data.winning_option_id = option::some(winning_option_id);
        
        // Emit prediction resolved event
        event::emit(PredictionResolvedEvent {
            post_id: prediction_data.post_id,
            winning_option_id,
            total_bet_amount: prediction_data.total_bet_amount,
            winning_amount,
            resolved_by: tx_context::sender(ctx),
        });
        
        // Distribute all winnings automatically
        
        // Calculate platform fee
        let total_bet_amount = prediction_data.total_bet_amount;
        let fee_amount = (total_bet_amount * config.prediction_fee_bps) / 10000;
        let distributable_amount = total_bet_amount - fee_amount;
        
        // Get all winners and their bet amounts
        let mut winners = vector::empty<address>();
        let mut winner_amounts = vector::empty<u64>();
        let mut winner_payouts = vector::empty<u64>();
        let mut total_payout = 0;
        
        let mut i = 0;
        let bets_len = vector::length(&prediction_data.bets);
        
        // First pass - identify winners and their bet amounts
        while (i < bets_len) {
            let bet = vector::borrow(&prediction_data.bets, i);
            if (bet.option_id == winning_option_id) {
                let winner = bet.user;
                let bet_amount = bet.amount;
                
                // Check if this user is already in the winners list
                let mut found = false;
                let mut winner_index = 0;
                let winners_len = vector::length(&winners);
                
                while (winner_index < winners_len && !found) {
                    if (*vector::borrow(&winners, winner_index) == winner) {
                        found = true;
                        // Add to their existing bet amount
                        let current_amount = vector::borrow_mut(&mut winner_amounts, winner_index);
                        *current_amount = *current_amount + bet_amount;
                    };
                    winner_index = winner_index + 1;
                };
                
                if (!found) {
                    // Add new winner
                    vector::push_back(&mut winners, winner);
                    vector::push_back(&mut winner_amounts, bet_amount);
                };
            };
            i = i + 1;
        };
        
        // Calculate payouts based on proportion of winning bets
        i = 0;
        let winners_len = vector::length(&winners);
        
        // Calculate payout ratios
        while (i < winners_len) {
            let bet_amount = *vector::borrow(&winner_amounts, i);
            // Calculate payout based on proportion of winning bets
            let payout = if (winning_amount == 0) {
                0 // Avoid division by zero
            } else {
                (((bet_amount as u128) * (distributable_amount as u128)) / (winning_amount as u128)) as u64
            };
            
            vector::push_back(&mut winner_payouts, payout);
            total_payout = total_payout + payout;
            i = i + 1;
        };
        
        // Ensure we have enough funds to distribute, including fee
        assert!(coin::value(payout_funds) >= total_bet_amount, EInvalidTipAmount);
        
        // First send the platform fee if applicable
        if (fee_amount > 0) {
            let fee_coin = coin::split(payout_funds, fee_amount, ctx);
            transfer::public_transfer(fee_coin, config.prediction_treasury);
        };
        
        // Distribute to all winners
        i = 0;
        
        while (i < winners_len) {
            let winner = *vector::borrow(&winners, i);
            let amount = *vector::borrow(&winner_payouts, i);
            
            if (amount > 0) {
                let payment = coin::split(payout_funds, amount, ctx);
                transfer::public_transfer(payment, winner);
                
                // Emit payout event
                event::emit(PredictionPayoutEvent {
                    post_id: prediction_data.post_id,
                    user: winner, 
                    amount,
                });
            };
            
            i = i + 1;
        };
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
        allow_comments: bool,
        allow_reactions: bool,
        allow_reposts: bool,
        allow_quotes: bool,
        allow_tips: bool,
        poc_badge_id: Option<ID>,
        revenue_redirect_to: Option<address>,
        revenue_redirect_percentage: Option<u64>,
        my_ip_id: Option<address>,
        promotion_id: Option<address>,
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
            allow_comments,
            allow_reactions,
            allow_reposts,
            allow_quotes,
            allow_tips,
            poc_badge_id,
            revenue_redirect_to,
            revenue_redirect_percentage,
            my_ip_id,
            promotion_id,
            disable_auto_pool: false,
            version: upgrade::current_version(),
        };
        
        // Get post ID before sharing
        let post_id = object::uid_to_address(&post.id);
        
        // Share object
        transfer::share_object(post);
        
        // Return the post ID
        post_id
    }

    /// Create a new post with interaction permissions
    public entry fun create_post(
        registry: &UsernameRegistry,
        platform_registry: &platform::PlatformRegistry,
        platform: &platform::Platform,
        block_list_registry: &block_list::BlockListRegistry,
        config: &PostConfig,
        content: String,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        allow_comments: Option<bool>,
        allow_reactions: Option<bool>,
        allow_reposts: Option<bool>,
        allow_quotes: Option<bool>,
        allow_tips: Option<bool>,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        
        // Look up the profile ID for the sender (for reference, not ownership)
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let profile_id = option::extract(&mut profile_id_option);
        
        // Check if platform is approved
        let platform_id = object::uid_to_address(platform::id(platform));
        assert!(platform::is_approved(platform_registry, platform_id), EUnauthorized);
        
        // Check if user has joined the platform
        let profile_id_obj = object::id_from_address(profile_id);
        assert!(platform::has_joined_platform(platform, profile_id_obj), EUserNotJoinedPlatform);
        
        // Check if the user is blocked by the platform
        let platform_address = object::uid_to_address(platform::id(platform));
        assert!(!block_list::is_blocked(block_list_registry, platform_address, owner), EUserBlockedByPlatform);
        
        // Validate content length using config
        assert!(string::length(&content) <= config.max_content_length, EContentTooLarge);
        
        // Validate metadata size if provided
        if (option::is_some(&metadata_json)) {
            let metadata_ref = option::borrow(&metadata_json);
            assert!(string::length(metadata_ref) <= config.max_metadata_size, EContentTooLarge);
        };
        
        // Convert and validate media URLs if provided
        let media_option = if (option::is_some(&media_urls)) {
            let urls_bytes = option::extract(&mut media_urls);
            
            // Validate media URLs count using config
            assert!(vector::length(&urls_bytes) <= config.max_media_urls, ETooManyMediaUrls);
            
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
        
        // Validate mentions if provided using config
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= config.max_mentions, EContentTooLarge);
        };
        
        // Set defaults for optional boolean parameters
        let final_allow_comments = if (option::is_some(&allow_comments)) {
            *option::borrow(&allow_comments)
        } else {
            true // Default to allowing comments
        };
        let final_allow_reactions = if (option::is_some(&allow_reactions)) {
            *option::borrow(&allow_reactions)
        } else {
            true // Default to allowing reactions
        };
        let final_allow_reposts = if (option::is_some(&allow_reposts)) {
            *option::borrow(&allow_reposts)
        } else {
            true // Default to allowing reposts
        };
        let final_allow_quotes = if (option::is_some(&allow_quotes)) {
            *option::borrow(&allow_quotes)
        } else {
            true // Default to allowing quotes
        };
        let final_allow_tips = if (option::is_some(&allow_tips)) {
            *option::borrow(&allow_tips)
        } else {
            true // Default to allowing tips
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
            final_allow_comments,
            final_allow_reactions,
            final_allow_reposts,
            final_allow_quotes,
            final_allow_tips,
            option::none(), // poc_badge_id
            option::none(), // revenue_redirect_to
            option::none(), // revenue_redirect_percentage
            option::none(), // my_ip_id
            option::none(), // promotion_id
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

    /// Create a comment on a post or a reply to another comment
    /// Returns the ID of the created comment
    public entry fun create_comment(
        registry: &UsernameRegistry,
        platform: &platform::Platform,
        block_list_registry: &BlockListRegistry,
        config: &PostConfig,
        parent_post: &mut Post,
        parent_comment_id: Option<address>,
        content: String,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        ctx: &mut TxContext
    ): address {
        let owner = tx_context::sender(ctx);
        
        // Look up the profile ID for the sender
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let profile_id = option::extract(&mut profile_id_option);
        
        // Check if user has joined the platform
        let profile_id_obj = object::id_from_address(profile_id);
        assert!(platform::has_joined_platform(platform, profile_id_obj), EUserNotJoinedPlatform);
        
        // Check if the user is blocked by the platform
        let platform_address = object::uid_to_address(platform::id(platform));
        assert!(!block_list::is_blocked(block_list_registry, platform_address, owner), EUserBlockedByPlatform);
        
        // Check if the caller is blocked by the post creator
        assert!(!block_list::is_blocked(block_list_registry, parent_post.owner, owner), EUnauthorized);
        
        // Check if comments are allowed on the parent post
        assert!(parent_post.allow_comments, ECommentsNotAllowed);
        
        // Validate content length using config
        assert!(string::length(&content) <= config.max_content_length, EContentTooLarge);
        
        // Validate metadata size if provided
        if (option::is_some(&metadata_json)) {
            let metadata_ref = option::borrow(&metadata_json);
            assert!(string::length(metadata_ref) <= config.max_metadata_size, EContentTooLarge);
        };
        
        // Convert and validate media URLs if provided
        let media_option = if (option::is_some(&media_urls)) {
            let urls_bytes = option::extract(&mut media_urls);
            
            // Validate media URLs count using config
            assert!(vector::length(&urls_bytes) <= config.max_media_urls, ETooManyMediaUrls);
            
            // Convert media URL bytes to Url objects
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
        
        // Validate mentions if provided using config
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= config.max_mentions, EContentTooLarge);
        };
        
        // Get parent post ID
        let parent_post_id = object::uid_to_address(&parent_post.id);
        
        // Create a proper Comment object instead of reusing post structure
        let comment = Comment {
            id: object::new(ctx),
            post_id: parent_post_id,
            parent_comment_id,
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
            version: upgrade::current_version(),
        };
        
        // Get comment ID before sharing
        let comment_id = object::uid_to_address(&comment.id);
        
        // Increment the parent post's comment count with overflow protection
        // Stop incrementing at max but allow commenting to continue
        if (parent_post.comment_count < MAX_U64) {
            parent_post.comment_count = parent_post.comment_count + 1;
        };
        
        // Emit comment created event
        event::emit(CommentCreatedEvent {
            comment_id,
            post_id: parent_post_id,
            parent_comment_id,
            owner,
            profile_id,
            content,
            mentions,
        });
        
        // Share the comment object
        transfer::share_object(comment);
        
        // Return the comment ID to the caller
        comment_id
    }

    /// Create a repost or quote repost depending on provided parameters
    /// If content is provided, it's treated as a quote repost
    /// If content is empty/none, it's treated as a standard repost
    public entry fun create_repost(
        registry: &UsernameRegistry,
        platform_registry: &platform::PlatformRegistry,
        platform: &platform::Platform,
        block_list_registry: &block_list::BlockListRegistry,
        config: &PostConfig,
        original_post: &mut Post,
        mut content: Option<String>,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        allow_comments: Option<bool>,
        allow_reactions: Option<bool>,
        allow_reposts: Option<bool>,
        allow_quotes: Option<bool>,
        allow_tips: Option<bool>,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        
        // Look up the profile ID for the sender (for reference, not ownership)
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let profile_id = option::extract(&mut profile_id_option);
        
        // Check if platform is approved
        let platform_id = object::uid_to_address(platform::id(platform));
        assert!(platform::is_approved(platform_registry, platform_id), EUnauthorized);
        
        // Check if user has joined the platform
        let profile_id_obj = object::id_from_address(profile_id);
        assert!(platform::has_joined_platform(platform, profile_id_obj), EUserNotJoinedPlatform);
        
        // Check if the user is blocked by the platform
        let platform_address = object::uid_to_address(platform::id(platform));
        assert!(!block_list::is_blocked(block_list_registry, platform_address, owner), EUserBlockedByPlatform);
        
        let original_post_id = object::uid_to_address(&original_post.id);
        
        // Determine if this is a quote repost or standard repost
        let is_quote_repost = option::is_some(&content) && string::length(option::borrow(&content)) > 0;
        
        // Check post permissions directly
        if (is_quote_repost) {
            // For quote reposts, check if quoting is allowed
            assert!(original_post.allow_quotes, EQuotesNotAllowed);
        } else {
            // For regular reposts, check if reposting is allowed
            assert!(original_post.allow_reposts, ERepostsNotAllowed);
        };
        
        // Initialize content string
        let content_string = if (is_quote_repost) {
            // Validate content length for quote reposts
            let content_value = option::extract(&mut content);
            // Use config value instead of hardcoded constant
            assert!(string::length(&content_value) <= config.max_content_length, EContentTooLarge);
            content_value
        } else {
            // Empty string for standard reposts
            string::utf8(b"")
        };
        
        // Validate and process media URLs if provided
        let media_option = if (option::is_some(&media_urls)) {
            let urls_bytes = option::extract(&mut media_urls);
            
            // Validate media URLs count
            assert!(vector::length(&urls_bytes) <= config.max_media_urls, ETooManyMediaUrls);
            
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
            assert!(string::length(metadata_ref) <= config.max_metadata_size, EContentTooLarge);
        };
        
        // Validate mentions if provided
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= config.max_mentions, EContentTooLarge);
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
                version: upgrade::current_version(),
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
        
        // Set defaults for optional boolean parameters
        let final_allow_comments = if (option::is_some(&allow_comments)) {
            *option::borrow(&allow_comments)
        } else {
            true // Default to allowing comments
        };
        let final_allow_reactions = if (option::is_some(&allow_reactions)) {
            *option::borrow(&allow_reactions)
        } else {
            true // Default to allowing reactions
        };
        let final_allow_reposts = if (option::is_some(&allow_reposts)) {
            *option::borrow(&allow_reposts)
        } else {
            true // Default to allowing reposts
        };
        let final_allow_quotes = if (option::is_some(&allow_quotes)) {
            *option::borrow(&allow_quotes)
        } else {
            true // Default to allowing quotes
        };
        let final_allow_tips = if (option::is_some(&allow_tips)) {
            *option::borrow(&allow_tips)
        } else {
            true // Default to allowing tips
        };
        
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
            final_allow_comments,
            final_allow_reactions,
            final_allow_reposts,
            final_allow_quotes,
            final_allow_tips,
            option::none(), // poc_badge_id
            option::none(), // revenue_redirect_to
            option::none(), // revenue_redirect_percentage
            option::none(), // No MyIP for reposts
            option::none(), // promotion_id
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
            allow_comments: _,
            allow_reactions: _,
            allow_reposts: _,
            allow_quotes: _,
            allow_tips: _,
            poc_badge_id: _,
            revenue_redirect_to: _,
            revenue_redirect_percentage: _,
            my_ip_id: _,
            promotion_id: _,
            disable_auto_pool: _,
            version: _,
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
            version: _,
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
        config: &PostConfig,
        reaction: String,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        
        // Validate reaction length using config
        assert!(string::length(&reaction) <= config.max_reaction_length, EReactionContentTooLong);
        
        // Check if reactions are allowed on this post
        assert!(post.allow_reactions, EReactionsNotAllowed);
        
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

    /// Tip a post creator with MySo tokens (with PoC revenue redirection support)
    public entry fun tip_post(
        post: &mut Post,
        coins: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Basic validation
        assert!(amount > 0, EInvalidTipAmount);
        let tipper = tx_context::sender(ctx);
        assert!(tipper != post.owner, ESelfTipping);

        // Verify this is not a repost or quote repost (those should use tip_repost instead)
        assert!(
            string::utf8(POST_TYPE_REPOST) != post.post_type && 
            string::utf8(POST_TYPE_QUOTE_REPOST) != post.post_type,
            EInvalidPostType
        );

        // Check if tips are allowed on this post
        assert!(post.allow_tips, ETipsNotAllowed);
        
        // Apply PoC redirection and transfer
        let actual_received = apply_poc_redirection_and_transfer(
            post,
            post.owner,
            amount,
            coins,
            tipper,
            object::uid_to_address(&post.id),
            true,
            ctx
        );
        
        // Record total tips received for this post
        post.tips_received = post.tips_received + actual_received;
        
        // Emit tip event for amount actually received by post owner
        if (actual_received > 0) {
            event::emit(TipEvent {
                object_id: object::uid_to_address(&post.id),
                from: tipper,
                to: post.owner,
                amount: actual_received,
                is_post: true,
            });
        };
    }

    /// Helper function to apply PoC revenue redirection and transfer coins
    /// Returns the amount actually received by the intended recipient
    fun apply_poc_redirection_and_transfer(
        post: &Post,
        intended_recipient: address,
        amount: u64,
        coins: &mut Coin<MYS>,
        tipper: address,
        object_id: address,
        is_post_event: bool,
        ctx: &mut TxContext
    ): u64 {
        // Check if this post has revenue redirection for the intended recipient
        if (intended_recipient == post.owner && 
            option::is_some(&post.revenue_redirect_to) && 
            option::is_some(&post.revenue_redirect_percentage)) {
            
            let redirect_percentage = *option::borrow(&post.revenue_redirect_percentage);
            let original_creator = *option::borrow(&post.revenue_redirect_to);
            
            if (redirect_percentage > 0) {
                // Calculate tip split
                let redirected_amount = (amount * redirect_percentage) / 100;
                let remaining_amount = amount - redirected_amount;
                
                // Take the tip amount out of the provided coin
                let mut tip_coins = coin::split(coins, amount, ctx);
                
                if (redirected_amount > 0) {
                    // Split tip for redirection
                    let redirected_coins = coin::split(&mut tip_coins, redirected_amount, ctx);
                    
                    // Transfer redirected amount to original creator
                    transfer::public_transfer(redirected_coins, original_creator);
                    
                    // Emit redirection event
                    event::emit(TipEvent {
                        object_id,
                        from: tipper,
                        to: original_creator,
                        amount: redirected_amount,
                        is_post: is_post_event,
                    });
                };
                
                if (remaining_amount > 0) {
                    // Transfer remaining amount to intended recipient
                    transfer::public_transfer(tip_coins, intended_recipient);
                } else {
                    coin::destroy_zero(tip_coins);
                };
                
                return remaining_amount
            };
        };
        
        // No redirection - normal transfer
        let tip_coins = coin::split(coins, amount, ctx);
        transfer::public_transfer(tip_coins, intended_recipient);
        amount
    }

        /// Internal function to update PoC result (called only from proof_of_creativity module)
    public(package) fun update_poc_result(
        post: &mut Post,
        result_type: u8, // 1 = badge issued, 2 = redirection applied
        badge_id: Option<ID>,
        redirect_to: Option<address>,
        redirect_percentage: Option<u64>
    ) {
        if (result_type == 1) {
            // PoC badge issued - content is original
            post.poc_badge_id = badge_id;
            post.revenue_redirect_to = option::none();
            post.revenue_redirect_percentage = option::none();
        } else if (result_type == 2) {
            // Revenue redirection applied - content is derivative
            post.poc_badge_id = option::none();
            post.revenue_redirect_to = redirect_to;
            post.revenue_redirect_percentage = redirect_percentage;
        };
    }

    /// Internal function to clear PoC data after dispute resolution
    public(package) fun clear_poc_data(post: &mut Post) {
        post.poc_badge_id = option::none();
        post.revenue_redirect_to = option::none();
        post.revenue_redirect_percentage = option::none();
    }
     
     /// Tip a repost with MySo tokens - applies 50/50 split between repost owner and original post owner
    public entry fun tip_repost(
        post: &mut Post, // The repost
        original_post: &mut Post, // The original post
        config: &PostConfig,
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
        
        // Check if tips are allowed on both posts
        assert!(post.allow_tips, ETipsNotAllowed);
        assert!(original_post.allow_tips, ETipsNotAllowed);
        
        // Skip split if repost owner and original post owner are the same
        if (post.owner == original_post.owner) {
            // Standard flow - apply PoC redirection for unified owner
            let actual_received = apply_poc_redirection_and_transfer(
                post,
                post.owner,
                amount,
                coin,
                tipper,
                object::uid_to_address(&post.id),
                true,
                ctx
            );
            
            post.tips_received = post.tips_received + actual_received;
            
            // Emit tip event for amount actually received
            if (actual_received > 0) {
                event::emit(TipEvent {
                    object_id: object::uid_to_address(&post.id),
                    from: tipper,
                    to: post.owner,
                    amount: actual_received,
                    is_post: true,
                });
            };
        } else {
            // Calculate split using config
            let repost_owner_amount = (amount * config.repost_tip_percentage) / 100;
            let original_owner_amount = amount - repost_owner_amount;
            
            // Apply PoC redirection for repost owner's share
            let repost_actual_received = apply_poc_redirection_and_transfer(
                post,
                post.owner,
                repost_owner_amount,
                coin,
                tipper,
                object::uid_to_address(&post.id),
                true,
                ctx
            );
            
            // Apply PoC redirection for original post owner's share
            let original_actual_received = apply_poc_redirection_and_transfer(
                original_post,
                original_post.owner,
                original_owner_amount,
                coin,
                tipper,
                object::uid_to_address(&original_post.id),
                true,
                ctx
            );
            
            // Update tip counters
            post.tips_received = post.tips_received + repost_actual_received;
            original_post.tips_received = original_post.tips_received + original_actual_received;
            
            // Emit tip events for amounts actually received
            if (repost_actual_received > 0) {
                event::emit(TipEvent {
                    object_id: object::uid_to_address(&post.id),
                    from: tipper,
                    to: post.owner,
                    amount: repost_actual_received,
                    is_post: true,
                });
            };
            
            if (original_actual_received > 0) {
                event::emit(TipEvent {
                    object_id: object::uid_to_address(&original_post.id),
                    from: tipper, 
                    to: original_post.owner,
                    amount: original_actual_received,
                    is_post: true,
                });
            };
        }
    }
    
    /// Tip a comment with MySo tokens
    /// Split is 80% to commenter, 20% to post owner (with PoC redirection on post owner's share)
    public entry fun tip_comment(
        comment: &mut Comment,
        post: &mut Post,
        config: &PostConfig,
        coin: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let tipper = tx_context::sender(ctx);
        
        // Check if amount is valid
        assert!(amount > 0 && coin::value(coin) >= amount, EInvalidTipAmount);
        
        // Prevent self-tipping
        assert!(tipper != comment.owner, ESelfTipping);
        
        // Check if tips are allowed on the post
        assert!(post.allow_tips, ETipsNotAllowed);
        
        // Calculate split based on config percentage
        let commenter_amount = (amount * config.commenter_tip_percentage) / 100;
        let post_owner_amount = amount - commenter_amount;
        
        // Transfer commenter's share directly (no PoC redirection for commenters)
        let commenter_tip = coin::split(coin, commenter_amount, ctx);
        transfer::public_transfer(commenter_tip, comment.owner);
        
        // Apply PoC redirection for post owner's share
        let post_owner_actual_received = apply_poc_redirection_and_transfer(
            post,
            post.owner,
            post_owner_amount,
            coin,
            tipper,
            object::uid_to_address(&post.id),
            true,
            ctx
        );
        
        // Update tip counters
        comment.tips_received = comment.tips_received + commenter_amount;
        post.tips_received = post.tips_received + post_owner_actual_received;
        
        // Emit tip event for commenter
        event::emit(TipEvent {
            object_id: object::uid_to_address(&comment.id),
            from: tipper,
            to: comment.owner,
            amount: commenter_amount,
            is_post: false,
        });
        
        // Emit tip event for post owner (amount actually received)
        if (post_owner_actual_received > 0) {
            event::emit(TipEvent {
                object_id: object::uid_to_address(&post.id),
                from: tipper,
                to: post.owner,
                amount: post_owner_actual_received,
                is_post: true,
            });
        };
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

    /// Admin function to transfer post ownership (requires PostAdminCap)
    public entry fun admin_transfer_post_ownership(
        _: &PostAdminCap,
        post: &mut Post,
        new_owner: address,
        registry: &UsernameRegistry,
        _ctx: &mut TxContext
    ) {
        // Admin capability verification is handled by type system
        
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
        config: &PostConfig,
        content: String,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        ctx: &mut TxContext
    ) {
        // Verify caller is the owner
        let owner = tx_context::sender(ctx);
        assert!(owner == post.owner, EUnauthorized);
        
        // Validate content length using config
        assert!(string::length(&content) <= config.max_content_length, EContentTooLarge);
        
        // Validate and update metadata if provided
        if (option::is_some(&metadata_json)) {
            let metadata_string = option::borrow(& metadata_json);
            assert!(string::length(metadata_string) <= config.max_metadata_size, EContentTooLarge);
            // Clear the current value and set the new one
            post.metadata_json = option::some(*metadata_string);
        };
        
        // Convert and validate media URLs if provided
        if (option::is_some(&media_urls)) {
            let urls_bytes = option::extract(&mut media_urls);
            
            // Validate media URLs count
            assert!(vector::length(&urls_bytes) <= config.max_media_urls, ETooManyMediaUrls);
            
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
        
        // Validate mentions if provided using config
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= config.max_mentions, EContentTooLarge);
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
        config: &PostConfig,
        content: String,
        mentions: Option<vector<address>>,
        ctx: &mut TxContext
    ) {
        // Verify caller is the owner
        let owner = tx_context::sender(ctx);
        assert!(owner == comment.owner, EUnauthorized);
        
        // Validate content length using config
        assert!(string::length(&content) <= config.max_content_length, EContentTooLarge);
        
        // Validate mentions if provided using config
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= config.max_mentions, EContentTooLarge);
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
        config: &PostConfig,
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
        
        // Validate description length using config
        assert!(string::length(&description) <= config.max_description_length, EReportDescriptionTooLong);
        
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
        config: &PostConfig,
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
        
        // Validate description length using config
        assert!(string::length(&description) <= config.max_description_length, EReportDescriptionTooLong);
        
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
        config: &PostConfig,
        reaction: String,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        
        // Validate reaction length using config
        assert!(string::length(&reaction) <= config.max_reaction_length, EReactionContentTooLong);
        
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

    /// Get the ID address of a post
    public fun get_id_address(post: &Post): address {
        object::uid_to_address(&post.id)
    }

    /// Get the reaction count of a post
    public fun get_reaction_count(post: &Post): u64 {
        post.reaction_count
    }

    /// Get the tips received for a post
    public fun get_tips_received(post: &Post): u64 {
        post.tips_received
    }

    /// Get the PoC badge ID for a post
    public fun get_poc_badge_id(post: &Post): &Option<ID> {
        &post.poc_badge_id
    }

    /// Get the revenue redirect address for a post
    public fun get_revenue_redirect_to(post: &Post): &Option<address> {
        &post.revenue_redirect_to
    }

    /// Get the revenue redirect percentage for a post
    public fun get_revenue_redirect_percentage(post: &Post): &Option<u64> {
        &post.revenue_redirect_percentage
    }

    /// Get total bet amount for a prediction
    public fun get_total_bet_amount(prediction_data: &PredictionData): u64 {
        prediction_data.total_bet_amount
    }
    
    /// Get number of bets for a prediction
    public fun get_bets_count(prediction_data: &PredictionData): u64 {
        vector::length(&prediction_data.bets)
    }
    
    /// Get bet user at index
    public fun get_bet_user(prediction_data: &PredictionData, index: u64): address {
        let bet = vector::borrow(&prediction_data.bets, index);
        bet.user
    }
    
    /// Get bet option id at index
    public fun get_bet_option_id(prediction_data: &PredictionData, index: u64): u8 {
        let bet = vector::borrow(&prediction_data.bets, index);
        bet.option_id
    }
    
    /// Get bet amount at index
    public fun get_bet_amount(prediction_data: &PredictionData, index: u64): u64 {
        let bet = vector::borrow(&prediction_data.bets, index);
        bet.amount
    }

    /// Test-only initialization function
    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        // Create and share post configuration with predictions enabled for testing
        transfer::share_object(
            PostConfig {
                id: object::new(ctx),
                predictions_enabled: true, // Enable predictions for testing
                prediction_fee_bps: 500, // Default 5% fee
                prediction_treasury: tx_context::sender(ctx), // Set to sender
                max_content_length: MAX_CONTENT_LENGTH,
                max_media_urls: MAX_MEDIA_URLS,
                max_mentions: MAX_MENTIONS,
                max_metadata_size: MAX_METADATA_SIZE,
                max_description_length: MAX_DESCRIPTION_LENGTH,
                max_reaction_length: MAX_REACTION_LENGTH,
                commenter_tip_percentage: COMMENTER_TIP_PERCENTAGE,
                repost_tip_percentage: REPOST_TIP_PERCENTAGE,
                max_prediction_options: MAX_PREDICTION_OPTIONS,
            }
        );
        
        // Create and transfer the admin capability for testing
        let admin_cap = PostAdminCap {
            id: object::new(ctx),
        };
        
        transfer::public_transfer(admin_cap, tx_context::sender(ctx));
    }
    
    /// Test-only function to create a post directly for testing
    #[test_only]
    public fun test_create_post(
        owner: address,
        profile_id: address,
        content: String,
        ctx: &mut TxContext
    ): address {
        create_post_internal(
            owner,
            profile_id,
            content,
            option::none(), // No media
            option::none(), // No mentions
            option::none(), // No metadata
            string::utf8(POST_TYPE_STANDARD), // Standard post type
            option::none(), // No parent post
            true, // allow_comments
            true, // allow_reactions
            true, // allow_reposts
            true, // allow_quotes
            true, // allow_tips
            option::none(), // poc_badge_id
            option::none(), // revenue_redirect_to
            option::none(), // revenue_redirect_percentage
            option::none(), // No MyIP ID
            option::none(), // promotion_id
            ctx
        )
    }
    
    /// Test-only function to create a promoted post directly for testing
    #[test_only]
    public fun create_test_promoted_post(
        owner: address,
        profile_id: address,
        content: String,
        payment_per_view: u64,
        promotion_budget: Coin<MYS>,
        ctx: &mut TxContext
    ): (address, address) {
        // Create promotion data
        let mut promotion_data = PromotionData {
            id: object::new(ctx),
            post_id: @0x0, // Will be set after post creation
            payment_per_view,
            promotion_budget: coin::into_balance(promotion_budget),
            paid_viewers: table::new(ctx),
            views: vector::empty(),
            active: false, // Starts inactive
            created_at: tx_context::epoch_timestamp_ms(ctx),
        };
        
        let promotion_id = object::uid_to_address(&promotion_data.id);
        
        // Create the post
        let post_id = create_post_internal(
            owner,
            profile_id,
            content,
            option::none(), // No media
            option::none(), // No mentions
            option::none(), // No metadata
            string::utf8(POST_TYPE_STANDARD),
            option::none(), // No parent post
            true, // allow_comments
            true, // allow_reactions
            true, // allow_reposts
            true, // allow_quotes
            true, // allow_tips
            option::none(), // poc_badge_id
            option::none(), // revenue_redirect_to
            option::none(), // revenue_redirect_percentage
            option::none(), // my_ip_id
            option::some(promotion_id), // promotion_id
            ctx
        );
        
        // Update promotion data with post ID
        promotion_data.post_id = post_id;
        
        // Share promotion data
        transfer::share_object(promotion_data);
        
        (post_id, promotion_id)
    }

    /// Test-only function to create a prediction post directly for testing
    #[test_only]
    public fun test_create_prediction_post(
        owner: address,
        profile_id: address,
        content: String,
        options: vector<String>,
        betting_end_time: Option<u64>,
        ctx: &mut TxContext
    ): (address, address) {
        // Create the post with prediction type
        let post_id = create_post_internal(
            owner,
            profile_id,
            content,
            option::none(), // No media
            option::none(), // No mentions
            option::none(), // No metadata
            string::utf8(POST_TYPE_PREDICTION), // Prediction post type
            option::none(), // No parent post
            true, // allow_comments
            true, // allow_reactions
            true, // allow_reposts
            true, // allow_quotes
            true, // allow_tips
            option::none(), // poc_badge_id
            option::none(), // revenue_redirect_to
            option::none(), // revenue_redirect_percentage
            option::none(), // my_ip_id
            option::none(), // promotion_id
            ctx
        );
        
        // Create prediction options
        let mut prediction_options = vector::empty<PredictionOption>();
        let mut i = 0;
        let options_len = vector::length(&options);
        
        while (i < options_len) {
            let option_desc = *vector::borrow(&options, i);
            
            let prediction_option = PredictionOption {
                id: (i as u8),
                description: option_desc,
                total_bet: 0
            };
            
            vector::push_back(&mut prediction_options, prediction_option);
            i = i + 1;
        };
        
        // Create prediction data
        let prediction_data = PredictionData {
            id: object::new(ctx),
            post_id,
            options: prediction_options,
            bets: vector::empty(),
            resolved: false,
            winning_option_id: option::none(),
            betting_end_time,
            total_bet_amount: 0,
        };
        
        let prediction_data_id = object::uid_to_address(&prediction_data.id);
        
        // Emit prediction created event
        event::emit(PredictionCreatedEvent {
            post_id,
            prediction_data_id,
            owner,
            profile_id,
            content,
            options,
            betting_end_time,
        });
        
        // Share prediction data
        transfer::share_object(prediction_data);
        
        (post_id, prediction_data_id)
    }
    
    /// Test-only function to get the admin cap ID
    #[test_only]
    public fun test_get_admin_cap(
        ctx: &mut TxContext
    ): address {
        // Create a new admin cap for testing
        let admin_cap = PostAdminCap {
            id: object::new(ctx),
        };
        
        let admin_cap_id = object::uid_to_address(&admin_cap.id);
        
        // Transfer to sender
        transfer::public_transfer(admin_cap, tx_context::sender(ctx));
        
        admin_cap_id
    }
    
    /// Test-only function to create a comment directly for testing
    #[test_only]
    public fun test_create_comment(
        owner: address,
        profile_id: address,
        post_id: address,
        content: String,
        ctx: &mut TxContext
    ): address {
        // Create a Comment object directly
        let comment = Comment {
            id: object::new(ctx),
            post_id,
            parent_comment_id: option::none(),
            owner,
            profile_id,
            content,
            media: option::none(),
            mentions: option::none(),
            metadata_json: option::none(),
            created_at: tx_context::epoch(ctx),
            reaction_count: 0,
            comment_count: 0,
            repost_count: 0,
            tips_received: 0,
            removed_from_platform: false,
            user_reactions: table::new(ctx),
            reaction_counts: table::new(ctx),
            version: upgrade::current_version(),
        };
        
        // Get comment ID before sharing
        let comment_id = object::uid_to_address(&comment.id);
        
        // Share the comment
        transfer::share_object(comment);
        
        // Return the comment ID
        comment_id
    }

    // === Versioning Functions ===

    /// Get the version of a post
    public fun version(post: &Post): u64 {
        post.version
    }

    /// Get a mutable reference to the post version (for upgrade module)
    public fun borrow_version_mut(post: &mut Post): &mut u64 {
        &mut post.version
    }

    /// Get the version of a comment
    public fun comment_version(comment: &Comment): u64 {
        comment.version
    }

    /// Get a mutable reference to the comment version (for upgrade module)
    public fun borrow_comment_version_mut(comment: &mut Comment): &mut u64 {
        &mut comment.version
    }

    /// Get the version of a repost
    public fun repost_version(repost: &Repost): u64 {
        repost.version
    }

    /// Get a mutable reference to the repost version (for upgrade module)
    public fun borrow_repost_version_mut(repost: &mut Repost): &mut u64 {
        &mut repost.version
    }

    /// Migration function for Post
    public entry fun migrate_post(
        post: &mut Post,
        _: &UpgradeAdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        
        // Verify this is an upgrade (new version > current version)
        assert!(post.version < current_version, EWrongVersion);
        
        // Remember old version and update to new version
        let old_version = post.version;
        post.version = current_version;
        
        // Emit event for object migration
        let post_id = object::id(post);
        upgrade::emit_migration_event(
            post_id,
            string::utf8(POST_TYPE_STANDARD),
            old_version,
            tx_context::sender(ctx)
        );
        
        // Any migration logic can be added here for future upgrades
    }

    /// Migration function for Comment
    public entry fun migrate_comment(
        comment: &mut Comment,
        _: &UpgradeAdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        
        // Verify this is an upgrade (new version > current version)
        assert!(comment.version < current_version, EWrongVersion);
        
        // Remember old version and update to new version
        let old_version = comment.version;
        comment.version = current_version;
        
        // Emit event for object migration
        let comment_id = object::id(comment);
        upgrade::emit_migration_event(
            comment_id,
            string::utf8(b"Comment"),
            old_version,
            tx_context::sender(ctx)
        );
        
        // Any migration logic can be added here for future upgrades
    }

    /// Migration function for Repost
    public entry fun migrate_repost(
        repost: &mut Repost,
        _: &UpgradeAdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        
        // Verify this is an upgrade (new version > current version)
        assert!(repost.version < current_version, EWrongVersion);
        
        // Remember old version and update to new version
        let old_version = repost.version;
        repost.version = current_version;
        
        // Emit event for object migration
        let repost_id = object::id(repost);
        upgrade::emit_migration_event(
            repost_id,
            string::utf8(b"Repost"),
            old_version,
            tx_context::sender(ctx)
        );
        
        // Any migration logic can be added here for future upgrades
    }



    /// Update post parameters (admin only)
    public entry fun update_post_parameters(
        _admin_cap: &PostAdminCap,
        config: &mut PostConfig,
        max_content_length: u64,
        max_media_urls: u64,
        max_mentions: u64,
        max_metadata_size: u64,
        max_description_length: u64,
        max_reaction_length: u64,
        commenter_tip_percentage: u64,
        repost_tip_percentage: u64,
        max_prediction_options: u64,
        ctx: &mut TxContext
    ) {
        // Validation
        assert!(commenter_tip_percentage <= 100, EInvalidConfig);
        assert!(repost_tip_percentage <= 100, EInvalidConfig);
        assert!(max_content_length > 0, EInvalidConfig);
        assert!(max_media_urls > 0, EInvalidConfig);
        assert!(max_mentions > 0, EInvalidConfig);
        
        // Update config
        config.max_content_length = max_content_length;
        config.max_media_urls = max_media_urls;
        config.max_mentions = max_mentions;
        config.max_metadata_size = max_metadata_size;
        config.max_description_length = max_description_length;
        config.max_reaction_length = max_reaction_length;
        config.commenter_tip_percentage = commenter_tip_percentage;
        config.repost_tip_percentage = repost_tip_percentage;
        config.max_prediction_options = max_prediction_options;
        
        // Emit update event
        event::emit(PostParametersUpdatedEvent {
            updated_by: tx_context::sender(ctx),
            timestamp: tx_context::epoch_timestamp_ms(ctx),
            max_content_length,
            max_media_urls,
            max_mentions,
            max_metadata_size,
            max_description_length,
            max_reaction_length,
            commenter_tip_percentage,
            repost_tip_percentage,
            max_prediction_options,
        });
    }

    /// Create a promoted post with MYS tokens for viewer payments
    public fun create_promoted_post(
        registry: &UsernameRegistry,
        platform_registry: &platform::PlatformRegistry,
        platform: &platform::Platform,
        _block_list_registry: &block_list::BlockListRegistry,
        config: &PostConfig,
        content: String,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        my_ip_id: Option<address>,
        payment_per_view: u64,
        promotion_budget: Coin<MYS>,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        
        // Validate promotion parameters
        assert!(payment_per_view >= MIN_PROMOTION_AMOUNT, EPromotionAmountTooLow);
        assert!(payment_per_view <= MAX_PROMOTION_AMOUNT, EPromotionAmountTooHigh);
        assert!(coin::value(&promotion_budget) >= payment_per_view, EInsufficientPromotionFunds);
        
        // Look up the profile ID for the sender
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let profile_id = option::extract(&mut profile_id_option);
        
        // Check if platform is approved 
        let platform_id = object::uid_to_address(platform::id(platform));
        assert!(platform::is_approved(platform_registry, platform_id), EUnauthorized);
        
        // Validate block list - simplified for this implementation
        // assert!(!block_list::is_profile_blocked(block_list_registry, profile_id), EUserBlockedByPlatform);
        
        // Validate content length using config
        assert!(string::length(&content) <= config.max_content_length, EContentTooLarge);
        
        // Validate and convert media URLs if provided
        let media_option = if (option::is_some(&media_urls)) {
            let urls_bytes = option::extract(&mut media_urls);
            assert!(vector::length(&urls_bytes) <= config.max_media_urls, ETooManyMediaUrls);
            
            let mut urls = vector::empty<Url>();
            let mut i = 0;
            while (i < vector::length(&urls_bytes)) {
                let url_bytes = vector::borrow(&urls_bytes, i);
                let url = url::new_unsafe_from_bytes(*url_bytes);
                vector::push_back(&mut urls, url);
                i = i + 1;
            };
            option::some(urls)
        } else {
            option::none()
        };
        
        // Validate mentions if provided using config
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= config.max_mentions, EContentTooLarge);
        };
        
        // Validate metadata if provided using config
        if (option::is_some(&metadata_json)) {
            let metadata_string = option::borrow(&metadata_json);
            assert!(string::length(metadata_string) <= config.max_metadata_size, EContentTooLarge);
        };
        
        // Create promotion data (starts as inactive until platform activates it)
        let mut promotion_data = PromotionData {
            id: object::new(ctx),
            post_id: @0x0, // Will be set after post creation
            payment_per_view,
            promotion_budget: coin::into_balance(promotion_budget),
            paid_viewers: table::new(ctx),
            views: vector::empty(),
            active: false, // Starts inactive until platform approves
            created_at: tx_context::epoch_timestamp_ms(ctx),
        };
        
        let promotion_id = object::uid_to_address(&promotion_data.id);
        
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
            true, // allow_comments
            true, // allow_reactions
            true, // allow_reposts
            true, // allow_quotes
            true, // allow_tips
            option::none(), // poc_badge_id
            option::none(), // revenue_redirect_to
            option::none(), // revenue_redirect_percentage
            my_ip_id,
            option::some(promotion_id),
            ctx
        );
        
        // Update promotion data with post ID
        promotion_data.post_id = post_id;
        
        // Get budget value before moving the promotion_data
        let total_budget = balance::value(&promotion_data.promotion_budget);
        
        // Share promotion data
        transfer::share_object(promotion_data);
        
        // Emit promoted post creation event
        event::emit(PromotedPostCreatedEvent {
            post_id,
            owner,
            profile_id,
            payment_per_view,
            total_budget,
            created_at: tx_context::epoch_timestamp_ms(ctx),
        });
    }

    /// Confirm a user has viewed a promoted post and pay them (platform only)
    public entry fun confirm_promoted_post_view(
        post: &Post,
        promotion_data: &mut PromotionData,
        platform_obj: &platform::Platform,
        viewer_address: address,
        view_duration: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Verify this is a platform call (platform developer or moderator)
        let caller = tx_context::sender(ctx);
        assert!(platform::is_developer_or_moderator(platform_obj, caller), EUnauthorized);
        
        // Verify the post is promoted
        assert!(option::is_some(&post.promotion_id), ENotPromotedPost);
        let post_promotion_id = *option::borrow(&post.promotion_id);
        assert!(post_promotion_id == object::uid_to_address(&promotion_data.id), ENotPromotedPost);
        
        // Verify promotion is active
        assert!(promotion_data.active, EPromotionInactive);
        
        // Verify view duration meets minimum requirement
        assert!(view_duration >= MIN_VIEW_DURATION, EInvalidViewDuration);
        
        // Verify user hasn't already been paid for viewing this post
        assert!(!table::contains(&promotion_data.paid_viewers, viewer_address), EUserAlreadyViewed);
        
        // Verify sufficient budget remains
        assert!(balance::value(&promotion_data.promotion_budget) >= promotion_data.payment_per_view, EInsufficientPromotionFunds);
        
        // Record the view
        let view_record = PromotionView {
            viewer: viewer_address,
            view_duration,
            view_timestamp: clock::timestamp_ms(clock),
            platform_id: caller, // Use caller as platform identifier
        };
        vector::push_back(&mut promotion_data.views, view_record);
        
        // Mark user as paid
        table::add(&mut promotion_data.paid_viewers, viewer_address, true);
        
        // Split payment from promotion budget and transfer to viewer
        let payment_balance = balance::split(&mut promotion_data.promotion_budget, promotion_data.payment_per_view);
        let payment_coin = coin::from_balance(payment_balance, ctx);
        transfer::public_transfer(payment_coin, viewer_address);
        
        // If budget is exhausted, deactivate promotion
        if (balance::value(&promotion_data.promotion_budget) < promotion_data.payment_per_view) {
            promotion_data.active = false;
        };
        
        // Emit view confirmation event
        event::emit(PromotedPostViewConfirmedEvent {
            post_id: post_promotion_id,
            viewer: viewer_address,
            payment_amount: promotion_data.payment_per_view,
            view_duration,
            platform_id: caller, // Use caller as platform identifier
            timestamp: clock::timestamp_ms(clock),
        });
    }


    /// Toggle promotion status (platform can activate, both platform and owner can deactivate)
    /// Use with activate: false to deactivate promotions
    public entry fun toggle_promotion_status(
        post: &Post,
        promotion_data: &mut PromotionData,
        platform_obj: &platform::Platform,
        activate: bool,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        
        // Verify the post is promoted
        assert!(option::is_some(&post.promotion_id), ENotPromotedPost);
        let post_promotion_id = *option::borrow(&post.promotion_id);
        assert!(post_promotion_id == object::uid_to_address(&promotion_data.id), ENotPromotedPost);
        
        if (activate) {
            // Only platform can activate promotions
            assert!(platform::is_developer_or_moderator(platform_obj, caller), EUnauthorized);
        } else {
            // Both platform and post owner can deactivate
            let is_platform = platform::is_developer_or_moderator(platform_obj, caller);
            let is_owner = caller == post.owner;
            assert!(is_platform || is_owner, EUnauthorized);
        };
        
        promotion_data.active = activate;
        
        // Emit status change event
        event::emit(PromotionStatusToggledEvent {
            post_id: post_promotion_id,
            toggled_by: caller,
            new_status: activate,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }

    /// Withdraw all MYS tokens from promotion (owner only, deactivates promotion)
    public entry fun withdraw_promotion_funds(
        post: &Post,
        promotion_data: &mut PromotionData,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        
        // Verify caller is post owner
        assert!(caller == post.owner, EUnauthorized);
        
        // Verify the post is promoted
        assert!(option::is_some(&post.promotion_id), ENotPromotedPost);
        let post_promotion_id = *option::borrow(&post.promotion_id);
        assert!(post_promotion_id == object::uid_to_address(&promotion_data.id), ENotPromotedPost);
        
        // Get remaining funds
        let remaining_amount = balance::value(&promotion_data.promotion_budget);
        
        // Extract all remaining balance and transfer to owner
        let withdrawn_balance = balance::withdraw_all(&mut promotion_data.promotion_budget);
        let withdrawn_coins = coin::from_balance(withdrawn_balance, ctx);
        transfer::public_transfer(withdrawn_coins, caller);
        
        // Deactivate promotion
        promotion_data.active = false;
        
        // Emit withdrawal event
        event::emit(PromotionFundsWithdrawnEvent {
            post_id: post_promotion_id,
            owner: caller,
            withdrawn_amount: remaining_amount,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }

    /// Get promotion statistics for a post
    public fun get_promotion_stats(promotion_data: &PromotionData): (u64, u64, bool, u64) {
        (
            promotion_data.payment_per_view,
            balance::value(&promotion_data.promotion_budget),
            promotion_data.active,
            vector::length(&promotion_data.views)
        )
    }

    /// Check if a user has already been paid for viewing a promoted post
    public fun has_user_viewed_promoted_post(promotion_data: &PromotionData, user: address): bool {
        table::contains(&promotion_data.paid_viewers, user)
    }

    /// Get the promotion ID from a post
    public fun get_promotion_id(post: &Post): Option<address> {
        post.promotion_id
    }

    /// Set moderation status for a post (platform devs/mods only)
    public entry fun set_moderation_status(
        post: &mut Post,
        platform: &platform::Platform,
        status: u8, // MODERATION_APPROVED or MODERATION_FLAGGED
        reason: Option<String>,
        ctx: &mut TxContext
    ) {
        // Verify caller is platform developer or moderator
        let caller = tx_context::sender(ctx);
        assert!(platform::is_developer_or_moderator(platform, caller), EUnauthorized);
        
        // Validate status
        assert!(status == MODERATION_APPROVED || status == MODERATION_FLAGGED, EUnauthorized);
        
        // Update post status based on moderation decision
        if (status == MODERATION_FLAGGED) {
            post.removed_from_platform = true;
        } else {
            post.removed_from_platform = false;
        };
        
        // Create or update moderation record
        let moderation_record = ModerationRecord {
            id: object::new(ctx),
            post_id: object::uid_to_address(&post.id),
            platform_id: object::uid_to_address(platform::id(platform)),
            moderation_state: status,
            moderator: option::some(caller),
            moderation_timestamp: option::some(tx_context::epoch_timestamp_ms(ctx)),
            reason,
        };
        
        transfer::share_object(moderation_record);
        
        // Emit moderation event
        event::emit(PostModerationEvent {
            post_id: object::uid_to_address(&post.id),
            platform_id: object::uid_to_address(platform::id(platform)),
            removed: (status == MODERATION_FLAGGED),
            moderated_by: caller,
        });
    }

    /// Check if content is approved (not flagged)
    public fun is_content_approved(post: &Post): bool {
        !post.removed_from_platform
    }

    #[test_only]
    public fun set_comment_count_for_testing(post: &mut Post, count: u64) {
        post.comment_count = count;
    }
    
    /// Create a PostAdminCap for bootstrap (package visibility only)
    /// This function is only callable by other modules in the same package
    public(package) fun create_post_admin_cap(ctx: &mut TxContext): PostAdminCap {
        PostAdminCap {
            id: object::new(ctx)
        }
    }
    
    #[test_only]
    /// Initialize the post module for testing
    /// In testing, we create admin caps directly for convenience
    public fun init_for_testing(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        
        // Create and transfer admin capability to the transaction sender
        transfer::public_transfer(
            PostAdminCap {
                id: object::new(ctx),
            },
            sender
        );
        
        // Create and share post configuration (same as production init)
        transfer::share_object(
            PostConfig {
                id: object::new(ctx),
                predictions_enabled: false, // Predictions disabled by default
                prediction_fee_bps: 500, // Default 5% fee
                prediction_treasury: sender, // Set to sender for testing
                max_content_length: MAX_CONTENT_LENGTH,
                max_media_urls: MAX_MEDIA_URLS,
                max_mentions: MAX_MENTIONS,
                max_metadata_size: MAX_METADATA_SIZE,
                max_description_length: MAX_DESCRIPTION_LENGTH,
                max_reaction_length: MAX_REACTION_LENGTH,
                commenter_tip_percentage: COMMENTER_TIP_PERCENTAGE,
                repost_tip_percentage: REPOST_TIP_PERCENTAGE,
                max_prediction_options: MAX_PREDICTION_OPTIONS,
            }
        );
    }
}
