// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Post module for the MySocial network
/// Handles creation and management of posts and comments
/// Implements features like comments, reposts, quotes, and predictions

module social_contracts::post {
    use std::string::{Self, String};
    
    use mys::event;
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::mys::MYS;
    use mys::url::{Self, Url};
    use mys::package::{Self, Publisher};
    
    use social_contracts::profile::UsernameRegistry;
    use social_contracts::platform;
    use social_contracts::block_list::{Self, BlockListRegistry};
    use social_contracts::upgrade::{Self, AdminCap};
    use social_contracts::my_ip::{Self, MyIPRegistry};

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
    const ELicenseNotRegistered: u64 = 27;

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
        /// Reference to the intellectual property license for the post
        my_ip_id: Option<address>,
        /// Version for upgrades
        version: u64,
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

    /// Admin capability for resolving predictions
    public struct PredictionAdminCap has key, store {
        id: UID,
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

    /// Global post feature configuration
    public struct PostConfig has key {
        id: UID,
        /// Indicates if prediction posts are enabled
        predictions_enabled: bool,
        /// Prediction platform fee in basis points (100 = 1%)
        prediction_fee_bps: u64,
        /// Treasury address for prediction fees
        prediction_treasury: address,
    }
    
    /// Initialize the post module
    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        
        // Create and share post configuration
        transfer::share_object(
            PostConfig {
                id: object::new(ctx),
                predictions_enabled: false, // Predictions disabled by default
                prediction_fee_bps: 500, // Default 5% fee
                prediction_treasury: sender, // Initially set to publisher
            }
        );
        
        // Create and transfer the admin capability to the module publisher
        let admin_cap = PredictionAdminCap {
            id: object::new(ctx),
        };
        
        transfer::transfer(admin_cap, sender);
    }
    
    /// Enable or disable prediction functionality (admin only)
    public entry fun set_predictions_enabled(
        publisher: &Publisher,
        config: &mut PostConfig,
        enabled: bool,
        _ctx: &mut TxContext
    ) {
        // Verify the publisher is for this module
        assert!(package::from_module<Post>(publisher), EUnauthorized);
        
        // Update configuration
        config.predictions_enabled = enabled;
    }
    
    /// Set prediction fee (admin only)
    public entry fun set_prediction_fee(
        publisher: &Publisher,
        config: &mut PostConfig,
        fee_bps: u64,
        treasury: address,
        _ctx: &mut TxContext
    ) {
        // Verify the publisher is for this module
        assert!(package::from_module<Post>(publisher), EUnauthorized);
        
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
        _admin_cap: &PredictionAdminCap,
        registry: &UsernameRegistry,
        platform: &platform::Platform,
        block_list_registry: &block_list::BlockListRegistry,
        content: String,
        options: vector<String>,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        betting_end_time: Option<u64>,
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
        assert!(platform::is_approved(platform), EUnauthorized);
        
        // Check if user has joined the platform
        let profile_id_obj = object::id_from_address(profile_id);
        assert!(platform::has_joined_platform(platform, profile_id_obj), EUserNotJoinedPlatform);
        
        // Check if the user is blocked by the platform
        let platform_address = object::uid_to_address(platform::id(platform));
        assert!(!block_list::is_blocked(block_list_registry, platform_address, owner), EUserBlockedByPlatform);
        
        // Validate content length
        assert!(string::length(&content) <= MAX_CONTENT_LENGTH, EContentTooLarge);
        
        // Validate options
        let options_length = vector::length(&options);
        assert!(options_length > 0, EPredictionOptionsEmpty);
        assert!(options_length <= MAX_PREDICTION_OPTIONS, EPredictionOptionsTooMany);
        
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
            option::none(),
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
        _admin_cap: &PredictionAdminCap,
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
        my_ip_id: Option<address>,
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
            my_ip_id,
            version: upgrade::current_version(),
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
        platform: &platform::Platform,
        block_list_registry: &block_list::BlockListRegistry,
        content: String,
        mut media_urls: Option<vector<vector<u8>>>,
        mentions: Option<vector<address>>,
        metadata_json: Option<String>,
        my_ip_id: Option<address>,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        
        // Look up the profile ID for the sender (for reference, not ownership)
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let profile_id = option::extract(&mut profile_id_option);
        
        // Check if platform is approved
        assert!(platform::is_approved(platform), EUnauthorized);
        
        // Check if user has joined the platform
        let profile_id_obj = object::id_from_address(profile_id);
        assert!(platform::has_joined_platform(platform, profile_id_obj), EUserNotJoinedPlatform);
        
        // Check if the user is blocked by the platform
        let platform_address = object::uid_to_address(platform::id(platform));
        assert!(!block_list::is_blocked(block_list_registry, platform_address, owner), EUserBlockedByPlatform);
        
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
            my_ip_id,
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
        my_ip_registry: &MyIPRegistry,
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
        
        // Check IP licensing permissions for comments if MyIP is attached to the parent post
        if (option::is_some(&parent_post.my_ip_id)) {
            let post_my_ip_id = *option::borrow(&parent_post.my_ip_id);
            assert!(my_ip::registry_is_commenting_allowed(my_ip_registry, post_my_ip_id, ctx), ECommentsNotAllowed);
        };
        
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
        
        // Validate mentions if provided
        if (option::is_some(&mentions)) {
            let mentions_ref = option::borrow(&mentions);
            assert!(vector::length(mentions_ref) <= MAX_MENTIONS, EContentTooLarge);
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
        
        // Increment the parent post's comment count
        parent_post.comment_count = parent_post.comment_count + 1;
        
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

    /// Create a repost (repost without comment)
    public entry fun repost(
        registry: &UsernameRegistry,
        platform: &platform::Platform,
        block_list_registry: &BlockListRegistry,
        my_ip_registry: &MyIPRegistry, // Added MyIPRegistry parameter
        original_post: &mut Post,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        
        // Look up the profile ID for the sender
        let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(registry, owner);
        assert!(option::is_some(&profile_id_option), EUnauthorized);
        let profile_id = option::extract(&mut profile_id_option);
        
        // Check if user is blocked by original post creator
        assert!(!block_list::is_blocked(block_list_registry, original_post.owner, owner), EUnauthorized);
        
        // Check if user has joined the platform
        let profile_id_obj = object::id_from_address(profile_id);
        assert!(platform::has_joined_platform(platform, profile_id_obj), EUserNotJoinedPlatform);
        
        // Check if the user is blocked by the platform
        let platform_address = object::uid_to_address(platform::id(platform));
        assert!(!block_list::is_blocked(block_list_registry, platform_address, owner), EUserBlockedByPlatform);
        
        // Check IP licensing permissions for reposts if MyIP is attached
        if (option::is_some(&original_post.my_ip_id)) {
            let my_ip_id = *option::borrow(&original_post.my_ip_id);
            assert!(my_ip::registry_is_reposting_allowed(my_ip_registry, my_ip_id, ctx), ERepostsNotAllowed);
        };
        
        // Get original post ID
        let original_post_id = object::uid_to_address(&original_post.id);
        
        // Create empty content for a repost
        let blank_content = string::utf8(b"");
        
        // Create and share the repost
        let repost_id = create_post_internal(
            owner,
            profile_id,
            blank_content,
            option::none(), // No media
            option::none(), // No mentions
            option::none(), // No metadata
            string::utf8(POST_TYPE_REPOST),
            option::some(original_post_id),
            option::none(), // No MyIP for reposts
            ctx
        );
        
        // Increment repost count on original post
        original_post.repost_count = original_post.repost_count + 1;
        
        // Emit repost created event
        event::emit(PostCreatedEvent {
            post_id: repost_id,
            owner,
            profile_id,
            content: blank_content,
            post_type: string::utf8(POST_TYPE_REPOST),
            parent_post_id: option::some(original_post_id),
            mentions: option::none(),
        });
    }
    
    /// Create a repost or quote repost depending on provided parameters
    /// If content is provided, it's treated as a quote repost
    /// If content is empty/none, it's treated as a standard repost
    public entry fun create_repost(
        registry: &UsernameRegistry,
        platform: &platform::Platform,
        block_list_registry: &block_list::BlockListRegistry,
        my_ip_registry: &my_ip::MyIPRegistry, // Added MyIPRegistry parameter
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
        
        // Check if platform is approved
        assert!(platform::is_approved(platform), EUnauthorized);
        
        // Check if user has joined the platform
        let profile_id_obj = object::id_from_address(profile_id);
        assert!(platform::has_joined_platform(platform, profile_id_obj), EUserNotJoinedPlatform);
        
        // Check if the user is blocked by the platform
        let platform_address = object::uid_to_address(platform::id(platform));
        assert!(!block_list::is_blocked(block_list_registry, platform_address, owner), EUserBlockedByPlatform);
        
        let original_post_id = object::uid_to_address(&original_post.id);
        
        // Determine if this is a quote repost or standard repost
        let is_quote_repost = option::is_some(&content) && string::length(option::borrow(&content)) > 0;
        
        // Check licensing permissions for the type of repost we're doing
        if (option::is_some(&original_post.my_ip_id)) {
            let my_ip_id = *option::borrow(&original_post.my_ip_id);
            
            if (is_quote_repost) {
                // For quote reposts, check if quoting is allowed
                assert!(my_ip::registry_is_quoting_allowed(my_ip_registry, my_ip_id, ctx), EQuotesNotAllowed);
            } else {
                // For regular reposts, check if reposting is allowed
                assert!(my_ip::registry_is_reposting_allowed(my_ip_registry, my_ip_id, ctx), ERepostsNotAllowed);
            }
        };
        
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
            option::none(), // No MyIP for reposts
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
            my_ip_id: _,
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
        registry: &my_ip::MyIPRegistry, // Added MyIPRegistry parameter
        reaction: String,
        ctx: &mut TxContext
    ) {
        let user = tx_context::sender(ctx);
        
        // Validate reaction length
        assert!(string::length(&reaction) <= MAX_REACTION_LENGTH, EReactionContentTooLong);
        
        // Check IP licensing permissions if MyIP is attached
        if (option::is_some(&post.my_ip_id)) {
            let my_ip_id = *option::borrow(&post.my_ip_id);
            assert!(my_ip::registry_is_reactions_allowed(registry, my_ip_id, ctx), EReactionsNotAllowed);
        };
        
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

    /// Tip a post creator with MYS tokens
    public entry fun tip_post(
        post: &mut Post,
        my_ip_registry: &my_ip::MyIPRegistry, // Added MyIPRegistry parameter
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

        // Check IP licensing permissions for tipping if MyIP is attached
        let mut revenue_recipient = post.owner; // Default recipient is post owner
        
        if (option::is_some(&post.my_ip_id)) {
            let my_ip_id = *option::borrow(&post.my_ip_id);
            
            // First check if tipping is allowed
            assert!(my_ip::registry_is_tipping_allowed(my_ip_registry, my_ip_id, ctx), ETipsNotAllowed);
            
            // Check if revenue should be redirected
            if (my_ip::registry_is_revenue_redirected(my_ip_registry, my_ip_id, ctx)) {
                // Revenue is redirected, get the recipient from registry
                revenue_recipient = my_ip::registry_get_revenue_recipient(my_ip_registry, my_ip_id);
            }
        };
        
        // Take the tip amount out of the provided coin
        let tip_coins = coin::split(coins, amount, ctx);
        
        // Record total tips received for this post
        post.tips_received = post.tips_received + amount;
        
        // Transfer tip to post owner (or revenue recipient)
        transfer::public_transfer(tip_coins, revenue_recipient);
        
        // Emit tip event
        event::emit(TipEvent {
            object_id: object::uid_to_address(&post.id),
            from: tipper,
            to: revenue_recipient,
            amount,
            is_post: true,
        });
    }
    
    /// Tip a repost with MYS tokens - applies 50/50 split between repost owner and original post owner
    public entry fun tip_repost(
        post: &mut Post, // The repost
        original_post: &mut Post, // The original post
        my_ip_registry: &my_ip::MyIPRegistry, // Added MyIPRegistry parameter
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
        
        // Check IP licensing permissions for tipping on the original post if MyIP is attached
        if (option::is_some(&original_post.my_ip_id)) {
            let my_ip_id = *option::borrow(&original_post.my_ip_id);
            assert!(my_ip::registry_is_tipping_allowed(my_ip_registry, my_ip_id, ctx), ETipsNotAllowed);
        };
        
        // Skip split if repost owner and original post owner are the same
        if (post.owner == original_post.owner) {
            // Standard flow - all goes to the same owner
            let tip_coin = coin::split(coin, amount, ctx);
            post.tips_received = post.tips_received + amount;
            transfer::public_transfer(tip_coin, post.owner);
            
            // Emit tip event
            event::emit(TipEvent {
                object_id: object::uid_to_address(&post.id),
                from: tipper,
                to: post.owner,
                amount,
                is_post: true,
            });
        } else {
            // Set up default recipients
            let repost_owner_recipient = post.owner;
            let mut original_owner_recipient = original_post.owner;
            
            // Check if revenue should be redirected for the original post
            if (option::is_some(&original_post.my_ip_id)) {
                let my_ip_id = *option::borrow(&original_post.my_ip_id);
                
                if (my_ip::registry_is_revenue_redirected(my_ip_registry, my_ip_id, ctx)) {
                    // Revenue is redirected, get the recipient from registry
                    original_owner_recipient = my_ip::registry_get_revenue_recipient(my_ip_registry, my_ip_id);
                }
            };
            
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
            transfer::public_transfer(tip_coin, repost_owner_recipient);
            
            // Transfer the original post owner's share
            transfer::public_transfer(original_owner_coin, original_owner_recipient);
            
            // Emit tip event for the repost owner
            event::emit(TipEvent {
                object_id: object::uid_to_address(&post.id),
                from: tipper,
                to: repost_owner_recipient,
                amount: repost_owner_amount,
                is_post: true,
            });
            
            // Emit tip event for the original post owner
            event::emit(TipEvent {
                object_id: object::uid_to_address(&original_post.id),
                from: tipper, 
                to: original_owner_recipient,
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
        my_ip_registry: &my_ip::MyIPRegistry,
        coin: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let tipper = tx_context::sender(ctx);
        
        // Check if amount is valid
        assert!(amount > 0 && coin::value(coin) >= amount, EInvalidTipAmount);
        
        // Prevent self-tipping
        assert!(tipper != comment.owner, ESelfTipping);
        
        // Set up default recipients
        let commenter_recipient = comment.owner;
        let mut post_owner_recipient = post.owner;
        
        // Check IP licensing permissions for tipping if MyIP is attached to the post
        if (option::is_some(&post.my_ip_id)) {
            let my_ip_id = *option::borrow(&post.my_ip_id);
            
            // First check if tipping is allowed
            assert!(my_ip::registry_is_tipping_allowed(my_ip_registry, my_ip_id, ctx), ETipsNotAllowed);
            
            // Check if revenue should be redirected for the post owner's share
            if (my_ip::registry_is_revenue_redirected(my_ip_registry, my_ip_id, ctx)) {
                // Revenue is redirected, get the recipient from registry
                post_owner_recipient = my_ip::registry_get_revenue_recipient(my_ip_registry, my_ip_id);
            }
        };
        
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
        transfer::public_transfer(tip_coin, commenter_recipient);
        
        // Transfer the post owner's share
        transfer::public_transfer(post_owner_coin, post_owner_recipient);
        
        // Emit tip event for commenter
        event::emit(TipEvent {
            object_id: object::uid_to_address(&comment.id),
            from: tipper,
            to: commenter_recipient,
            amount: commenter_amount,
            is_post: false,
        });
        
        // Emit tip event for post owner
        event::emit(TipEvent {
            object_id: object::uid_to_address(&post.id),
            from: tipper,
            to: post_owner_recipient,
            amount: post_owner_amount,
            is_post: true,
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
        _ctx: &mut TxContext
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

    /// Get the ID address of a post
    public fun get_id_address(post: &Post): address {
        object::uid_to_address(&post.id)
    }

    /// Get the owner of a post
    public fun get_owner(post: &Post): address {
        post.owner
    }

    /// Get the reaction count of a post
    public fun get_reaction_count(post: &Post): u64 {
        post.reaction_count
    }

    /// Get the comment count of a post
    public fun get_comment_count(post: &Post): u64 {
        post.comment_count
    }

    /// Get the tips received for a post
    public fun get_tips_received(post: &Post): u64 {
        post.tips_received
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
            }
        );
        
        // Create and transfer the admin capability for testing
        let admin_cap = PredictionAdminCap {
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
            option::none(), // No MyIP ID
            ctx
        )
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
            option::none(), // No MyIP ID
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
        let admin_cap = PredictionAdminCap {
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
        _: &AdminCap,
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
        _: &AdminCap,
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
        _: &AdminCap,
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

    /// Get the MyIP ID from a post (if any)
    public fun my_ip_id(post: &Post): &Option<address> {
        &post.my_ip_id
    }
    
    /// Check if a post has an attached MyIP license
    public fun has_my_ip(post: &Post): bool {
        option::is_some(&post.my_ip_id)
    }
    
    /// Attach a MyIP license to a post (only owner can do this)
    public entry fun attach_my_ip(
        post: &mut Post,
        my_ip_registry: &my_ip::MyIPRegistry, // Added MyIPRegistry parameter
        my_ip_id: address, // Now just passing the ID
        ctx: &mut TxContext
    ) {
        // Verify caller is the post owner
        assert!(tx_context::sender(ctx) == post.owner, EUnauthorized);
        
        // Verify the MyIP exists in the registry
        assert!(my_ip::is_registered(my_ip_registry, my_ip_id), ELicenseNotRegistered);
        
        // Verify caller is the MyIP creator
        let creator = my_ip::registry_get_creator(my_ip_registry, my_ip_id);
        assert!(tx_context::sender(ctx) == creator, EUnauthorized);
        
        // Set the MyIP ID
        post.my_ip_id = option::some(my_ip_id);
    }
    
    /// Remove the MyIP license from a post (only owner can do this)
    public entry fun remove_my_ip(
        post: &mut Post,
        _ctx: &mut TxContext
    ) {
        // Verify caller is the post owner
        assert!(tx_context::sender(_ctx) == post.owner, EUnauthorized);
        
        // Remove the MyIP ID
        post.my_ip_id = option::none();
    }

    /// Increment the comment count for a post
    public entry fun increment_comment_count(
        post: &mut Post,
        block_list_registry: &BlockListRegistry,
        my_ip_registry: &my_ip::MyIPRegistry,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        
        // Check if the caller is blocked by the post creator
        assert!(!block_list::is_blocked(block_list_registry, post.owner, caller), EUnauthorized);
        
        // Check IP licensing permissions for comments if MyIP is attached to the post
        if (option::is_some(&post.my_ip_id)) {
            let post_my_ip_id = *option::borrow(&post.my_ip_id);
            assert!(my_ip::registry_is_commenting_allowed(my_ip_registry, post_my_ip_id, ctx), ECommentsNotAllowed);
        };
        
        // Increment comment count
        post.comment_count = post.comment_count + 1;
    }
}