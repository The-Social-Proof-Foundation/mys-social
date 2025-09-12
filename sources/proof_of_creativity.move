// Copyright (c) The Social Proof Foundation, LLC.
// SPDX-License-Identifier: Apache-2.0

/// Proof of Creativity module for the MySocial network
/// Manages content originality verification through oracle analysis,
/// PoC badge issuance, revenue redirection, and community dispute voting

#[allow(duplicate_alias, unused_use, unused_const, unused_variable)]
module social_contracts::proof_of_creativity {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    
    use mys::{
        object::{Self, UID, ID},
        tx_context::{Self, TxContext},
        transfer,
        event,
        table::{Self, Table},
        coin::{Self, Coin},
        balance::{Self, Balance}
    };
    use mys::mys::MYS;
    use social_contracts::upgrade::{Self, UpgradeAdminCap};

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EInvalidThreshold: u64 = 2;
    const EPostNotFound: u64 = 3;
    const EInvalidMediaType: u64 = 7;
    const EInsufficientFunds: u64 = 9;
    const EWrongVersion: u64 = 11;
    const ENotOracle: u64 = 12;
    const EInvalidStakeAmount: u64 = 14;
    const EVotingNotActive: u64 = 15;
    const EVotingEnded: u64 = 16;
    const EAlreadyVoted: u64 = 17;
    const ENoVotesToResolve: u64 = 18;

    /// Media type constants
    const MEDIA_TYPE_IMAGE: u8 = 1;
    const MEDIA_TYPE_VIDEO: u8 = 2;
    const MEDIA_TYPE_AUDIO: u8 = 3;

    /// Dispute status constants
    const DISPUTE_STATUS_VOTING: u8 = 1;
    const DISPUTE_STATUS_RESOLVED_UPHELD: u8 = 2;  // Badge keeper wins
    const DISPUTE_STATUS_RESOLVED_OVERTURNED: u8 = 3;  // Challenger wins

    /// Vote option constants
    const VOTE_UPHOLD: u8 = 1;  // Keep original PoC decision
    const VOTE_OVERTURN: u8 = 2; // Overturn original PoC decision

    /// Configuration constants (default values)
    const DEFAULT_IMAGE_THRESHOLD: u64 = 95; // 0.95 as percentage (95/100)
    const DEFAULT_VIDEO_THRESHOLD: u64 = 95; // 0.95 as percentage
    const DEFAULT_AUDIO_THRESHOLD: u64 = 95; // 0.95 as percentage
    const DEFAULT_REVENUE_REDIRECT_PERCENTAGE: u64 = 100; // 100%
    const DEFAULT_DISPUTE_COST: u64 = 5_000_000_000; // 5 MYS
    const DEFAULT_DISPUTE_PROTOCOL_FEE: u64 = 1_000_000_000; // 1 MYS
    const DEFAULT_MIN_VOTE_STAKE: u64 = 1_000_000_000; // 1 MYS minimum to vote
    const DEFAULT_MAX_VOTE_STAKE: u64 = 100_000_000_000; // 100 MYS maximum per vote
    const DEFAULT_VOTING_DURATION_EPOCHS: u64 = 7; // 7 epochs voting period

    /// Admin capability for Proof of Creativity system management
    public struct PoCAdminCap has key, store {
        id: UID,
    }

    /// Global configuration for Proof of Creativity system
    public struct PoCConfig has key {
        id: UID,
        /// Oracle address authorized to submit analysis results
        oracle_address: address,
        /// Similarity thresholds for different media types (stored as percentages 0-100)
        image_threshold: u64,
        video_threshold: u64,
        audio_threshold: u64,
        /// Percentage of revenue to redirect when similarity detected (0-100)
        revenue_redirect_percentage: u64,
        /// Cost to submit a dispute
        dispute_cost: u64,
        /// Protocol fee for disputes (goes to ecosystem treasury)
        dispute_protocol_fee: u64,
        /// Minimum stake amount required to vote on disputes
        min_vote_stake: u64,
        /// Maximum stake amount allowed per vote
        max_vote_stake: u64,
        /// Voting duration in epochs
        voting_duration_epochs: u64,
        /// Governance registry ID for PoC disputes
        dispute_governance_id: ID,
        /// Ecosystem treasury address
        ecosystem_treasury: address,
        /// Version for upgrades
        version: u64,
    }

    /// Individual vote record in a dispute
    public struct Vote has store, copy, drop {
        /// Voter's address
        voter: address,
        /// Vote choice (VOTE_UPHOLD or VOTE_OVERTURN)
        vote_choice: u8,
        /// Amount of MySo staked with this vote
        stake_amount: u64,
        /// Epoch when vote was cast
        voted_at: u64,
    }

    /// Dispute challenging a PoC badge or revenue redirection with community voting
    public struct PoCDispute has key {
        id: UID,
        /// Post being disputed
        post_id: address,
        /// Address that submitted the dispute (post owner)
        disputer: address,
        /// Type of dispute (challenging badge or redirection)
        dispute_type: u8, // 1=challenge badge, 2=challenge redirection
        /// Current status of dispute
        status: u8,
        /// Evidence or reasoning provided by disputer
        evidence: String,
        /// Dispute submission timestamp
        submitted_at: u64,
        /// Epoch when voting starts
        voting_start_epoch: u64,
        /// Epoch when voting ends
        voting_end_epoch: u64,
        /// All votes cast on this dispute
        votes: vector<Vote>,
        /// Total stake on uphold side
        uphold_stake: u64,
        /// Total stake on overturn side
        overturn_stake: u64,
        /// Mapping of voter addresses to prevent double voting
        voter_records: Table<address, bool>,
        /// Total reward pool from losing side (set after resolution)
        reward_pool: Balance<MYS>,
        /// Version for upgrades
        version: u64,
    }

    /// Simplified registry to track PoC statistics
    public struct PoCRegistry has key {
        id: UID,
        /// Total badges issued
        total_badges_issued: u64,
        /// Total redirections created
        total_redirections_created: u64,
        /// Total disputes submitted
        total_disputes_submitted: u64,
        /// Total votes cast across all disputes
        total_votes_cast: u64,
        /// Version for upgrades
        version: u64,
    }

    // === Events ===

    /// Event emitted when oracle submits analysis results
    public struct AnalysisSubmittedEvent has copy, drop {
        post_id: address,
        media_type: u8,
        similarity_detected: bool,
        highest_similarity_score: u64,
        oracle_address: address,
        timestamp: u64,
    }

    /// Event emitted when a PoC badge is issued
    public struct PoCBadgeIssuedEvent has copy, drop {
        badge_id: address,
        post_id: address,
        media_type: u8,
        issued_by: address,
        timestamp: u64,
    }

    /// Event emitted when revenue redirection is activated
    public struct RevenueRedirectionActivatedEvent has copy, drop {
        redirection_id: address,
        accused_post_id: address,
        original_post_id: address,
        redirect_percentage: u64,
        similarity_score: u64,
        timestamp: u64,
    }

    /// Event emitted when a PoC dispute is submitted
    public struct PoCDisputeSubmittedEvent has copy, drop {
        dispute_id: address,
        post_id: address,
        disputer: address,
        dispute_type: u8,
        stake_amount: u64,
        voting_start_epoch: u64,
        voting_end_epoch: u64,
        timestamp: u64,
    }

    /// Event emitted when a vote is cast on a dispute
    public struct DisputeVoteCastEvent has copy, drop {
        dispute_id: address,
        voter: address,
        vote_choice: u8,
        stake_amount: u64,
        total_uphold_stake: u64,
        total_overturn_stake: u64,
        timestamp: u64,
    }

    /// Event emitted when a dispute is resolved
    public struct PoCDisputeResolvedEvent has copy, drop {
        dispute_id: address,
        post_id: address,
        resolution: u8, // upheld or overturned
        winning_side: u8, // VOTE_UPHOLD or VOTE_OVERTURN
        total_winning_stake: u64,
        total_losing_stake: u64,
        badge_revoked: bool,
        redirection_removed: bool,
        timestamp: u64,
    }

    /// Event emitted when voting rewards are claimed
    public struct VotingRewardClaimedEvent has copy, drop {
        dispute_id: address,
        voter: address,
        original_stake: u64,
        reward_amount: u64,
        total_payout: u64,
        timestamp: u64,
    }

    /// Event emitted when PoC configuration is updated
    public struct PoCConfigUpdatedEvent has copy, drop {
        updated_by: address,
        image_threshold: u64,
        video_threshold: u64,
        audio_threshold: u64,
        revenue_redirect_percentage: u64,
        dispute_cost: u64,
        min_vote_stake: u64,
        max_vote_stake: u64,
        voting_duration_epochs: u64,
        timestamp: u64,
    }

    /// Event emitted when token pool synchronization is needed
    public struct TokenPoolSyncNeededEvent has copy, drop {
        post_id: address,
        timestamp: u64,
    }

    // === Utility Functions ===

    /// Bootstrap initialization function - creates the PoC configuration and registry
    public(package) fun bootstrap_init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        
        // Create and share PoC configuration
        transfer::share_object(
            PoCConfig {
                id: object::new(ctx),
                oracle_address: sender, // Initially set to deployer, should be updated
                image_threshold: DEFAULT_IMAGE_THRESHOLD,
                video_threshold: DEFAULT_VIDEO_THRESHOLD,
                audio_threshold: DEFAULT_AUDIO_THRESHOLD,
                revenue_redirect_percentage: DEFAULT_REVENUE_REDIRECT_PERCENTAGE,
                dispute_cost: DEFAULT_DISPUTE_COST,
                dispute_protocol_fee: DEFAULT_DISPUTE_PROTOCOL_FEE,
                min_vote_stake: DEFAULT_MIN_VOTE_STAKE,
                max_vote_stake: DEFAULT_MAX_VOTE_STAKE,
                voting_duration_epochs: DEFAULT_VOTING_DURATION_EPOCHS,
                dispute_governance_id: object::id_from_address(@0x0), // Placeholder for future governance
                ecosystem_treasury: sender, // Auto-configured by bootstrap service during bootstrap
                version: upgrade::current_version(),
            }
        );
        
        // Create and share PoC registry
        transfer::share_object(
            PoCRegistry {
                id: object::new(ctx),
                total_badges_issued: 0,
                total_redirections_created: 0,
                total_disputes_submitted: 0,
                total_votes_cast: 0,
                version: upgrade::current_version(),
            }
        );
    }

    /// Update PoC configuration (admin only)
    public entry fun update_poc_config(
        _: &PoCAdminCap,
        config: &mut PoCConfig,
        oracle_address: address,
        image_threshold: u64,
        video_threshold: u64,
        audio_threshold: u64,
        revenue_redirect_percentage: u64,
        dispute_cost: u64,
        dispute_protocol_fee: u64,
        min_vote_stake: u64,
        max_vote_stake: u64,
        voting_duration_epochs: u64,
        ecosystem_treasury: address,
        ctx: &mut TxContext
    ) {
        // Admin capability verification is handled by type system
        
        // Validate thresholds (0-100)
        assert!(image_threshold <= 100, EInvalidThreshold);
        assert!(video_threshold <= 100, EInvalidThreshold);
        assert!(audio_threshold <= 100, EInvalidThreshold);
        assert!(revenue_redirect_percentage <= 100, EInvalidThreshold);
        
        // Validate voting parameters
        assert!(min_vote_stake > 0 && min_vote_stake <= max_vote_stake, EInvalidStakeAmount);
        assert!(voting_duration_epochs > 0, EInvalidThreshold);
        
        // Update configuration
        config.oracle_address = oracle_address;
        config.image_threshold = image_threshold;
        config.video_threshold = video_threshold;
        config.audio_threshold = audio_threshold;
        config.revenue_redirect_percentage = revenue_redirect_percentage;
        config.dispute_cost = dispute_cost;
        config.dispute_protocol_fee = dispute_protocol_fee;
        config.min_vote_stake = min_vote_stake;
        config.max_vote_stake = max_vote_stake;
        config.voting_duration_epochs = voting_duration_epochs;
        config.ecosystem_treasury = ecosystem_treasury;
        
        // Emit configuration update event
        event::emit(PoCConfigUpdatedEvent {
            updated_by: tx_context::sender(ctx),
            image_threshold,
            video_threshold,
            audio_threshold,
            revenue_redirect_percentage,
            dispute_cost,
            min_vote_stake,
            max_vote_stake,
            voting_duration_epochs,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }

    /// SINGLE ENTRY POINT: Oracle analyzes content and updates post PoC status
    /// This is the ONLY function the PoC server needs to call
    /// Automatically updates token pool if it exists
    public entry fun analyze_and_update_post(
        config: &PoCConfig,
        registry: &mut PoCRegistry,
        token_registry: &social_contracts::social_proof_tokens::TokenRegistry,
        post: &mut social_contracts::post::Post,
        media_type: u8,
        highest_similarity_score: u64,
        mut original_creator: Option<address>,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let timestamp = tx_context::epoch_timestamp_ms(ctx);
        let post_id = social_contracts::post::get_id_address(post);
        
        // Verify caller is authorized oracle
        assert!(caller == config.oracle_address, ENotOracle);
        
        // Verify media type is valid
        assert!(
            media_type == MEDIA_TYPE_IMAGE || 
            media_type == MEDIA_TYPE_VIDEO || 
            media_type == MEDIA_TYPE_AUDIO,
            EInvalidMediaType
        );
        
        // Get threshold for this media type
        let threshold = get_threshold_for_media_type(config, media_type);
        
        // Determine if similarity exceeds threshold and original creator exists
        let similarity_detected = highest_similarity_score >= threshold && option::is_some(&original_creator);
        
        if (similarity_detected) {
            // Content is derivative - apply revenue redirection
            let original_creator_address = option::extract(&mut original_creator);
            
            // Calculate redirect percentage using the same formula as before
            let delta_numerator = highest_similarity_score - threshold;
            let delta_denominator = 100 - threshold;
            let delta_percentage = if (delta_denominator > 0) {
                (delta_numerator * 100) / delta_denominator
            } else {
                100 // If threshold is 100, redirect 100%
            };
            let redirect_percentage = (config.revenue_redirect_percentage * delta_percentage) / 100;
            
            // Update post with redirection info
            social_contracts::post::update_poc_result(
                post,
                2, // redirection applied
                option::none(), // no badge
                option::some(original_creator_address), // redirect to original creator
                option::some(redirect_percentage) // redirect percentage
            );
            
            // Update registry tracking
            registry.total_redirections_created = registry.total_redirections_created + 1;
            
            // Emit simplified event
            event::emit(RevenueRedirectionActivatedEvent {
                redirection_id: post_id, // Use post ID as redirection ID
                accused_post_id: post_id,
                original_post_id: original_creator_address,
                redirect_percentage,
                similarity_score: highest_similarity_score,
                timestamp,
            });
        } else {
            // Content is original - issue PoC badge
            let badge_id = object::id_from_address(post_id); // Use post ID as badge ID
            
            // Update post with badge info
            social_contracts::post::update_poc_result(
                post,
                1, // badge issued
                option::some(badge_id), // badge ID
                option::none(), // no redirection
                option::none() // no redirection percentage
            );
            
            // Update registry tracking
            registry.total_badges_issued = registry.total_badges_issued + 1;
            
            // Emit simplified event
            event::emit(PoCBadgeIssuedEvent {
                badge_id: post_id, // Use post ID as badge ID
                post_id,
                media_type,
                issued_by: caller,
                timestamp,
            });
        };
        
        // Emit analysis event
        event::emit(AnalysisSubmittedEvent {
            post_id,
            media_type,
            similarity_detected,
            highest_similarity_score,
            oracle_address: caller,
            timestamp,
        });
        
        // Automatically update token pool if it exists
        update_token_pool_if_exists(token_registry, post, ctx);
    }

    /// Helper function to check if token pool sync is needed
    /// This ensures token pools are automatically synchronized with PoC results
    fun update_token_pool_if_exists(
        token_registry: &social_contracts::social_proof_tokens::TokenRegistry,
        post: &social_contracts::post::Post,
        _ctx: &mut TxContext
    ) {
        let post_id = social_contracts::post::get_id_address(post);
        
        // Check if a token pool exists for this post
        if (social_contracts::social_proof_tokens::token_exists(token_registry, post_id)) {
            // Token pool exists - emit event for automatic synchronization
            // The off-chain system can listen for this event and call update_token_poc_data
            event::emit(TokenPoolSyncNeededEvent {
                post_id,
                timestamp: tx_context::epoch_timestamp_ms(_ctx),
            });
        };
    }

    /// Submit a PoC dispute with community voting
    public entry fun submit_poc_dispute(
        config: &PoCConfig,
        registry: &mut PoCRegistry,
        post: &mut social_contracts::post::Post,
        evidence: String,
        mut payment: Coin<MYS>,
        ctx: &mut TxContext
    ) {
        let disputer = tx_context::sender(ctx);
        let timestamp = tx_context::epoch_timestamp_ms(ctx);
        let current_epoch = tx_context::epoch(ctx);
        let post_id = social_contracts::post::get_id_address(post);
        
        // Verify sufficient payment
        let total_cost = config.dispute_cost + config.dispute_protocol_fee;
        assert!(coin::value(&payment) >= total_cost, EInsufficientFunds);
        
        // Verify only post owner can dispute their post's PoC status
        assert!(disputer == social_contracts::post::get_post_owner(post), EUnauthorized);
        
        // Verify the post has PoC data to dispute (badge or redirection)
        let has_poc_data = option::is_some(social_contracts::post::get_poc_badge_id(post)) ||
                          option::is_some(social_contracts::post::get_revenue_redirect_to(post));
        assert!(has_poc_data, EPostNotFound);
        
        // Extract dispute fee and send to ecosystem treasury
        let dispute_fee = coin::split(&mut payment, total_cost, ctx);
        transfer::public_transfer(dispute_fee, config.ecosystem_treasury);
        
        // Return excess payment
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, disputer);
        } else {
            coin::destroy_zero(payment);
        };
        
        // Calculate voting period - start next epoch, end after voting duration
        let voting_start_epoch = current_epoch + 1;
        let voting_end_epoch = voting_start_epoch + config.voting_duration_epochs;
        
        // Create dispute with voting mechanism
        let dispute = PoCDispute {
            id: object::new(ctx),
            post_id,
            disputer,
            dispute_type: 1, // Generic PoC dispute
            status: DISPUTE_STATUS_VOTING,
            evidence,
            submitted_at: timestamp,
            voting_start_epoch,
            voting_end_epoch,
            votes: vector::empty(),
            uphold_stake: 0,
            overturn_stake: 0,
            voter_records: table::new(ctx),
            reward_pool: balance::zero(),
            version: upgrade::current_version(),
        };
        
        let dispute_id = object::uid_to_address(&dispute.id);
        
        // Update registry tracking
        registry.total_disputes_submitted = registry.total_disputes_submitted + 1;
        
        // Emit dispute submitted event
        event::emit(PoCDisputeSubmittedEvent {
            dispute_id,
            post_id,
            disputer,
            dispute_type: 1,
            stake_amount: total_cost,
            voting_start_epoch,
            voting_end_epoch,
            timestamp,
        });
        
        // Share dispute for public voting
        transfer::share_object(dispute);
    }

    /// Cast a vote on a PoC dispute (community voting)
    public entry fun vote_on_dispute(
        config: &PoCConfig,
        registry: &mut PoCRegistry,
        dispute: &mut PoCDispute,
        vote_choice: u8, // VOTE_UPHOLD or VOTE_OVERTURN
        stake_coin: Coin<MYS>,
        ctx: &mut TxContext
    ) {
        let voter = tx_context::sender(ctx);
        let current_epoch = tx_context::epoch(ctx);
        let timestamp = tx_context::epoch_timestamp_ms(ctx);
        let stake_amount = coin::value(&stake_coin);
        
        // Validate vote choice
        assert!(vote_choice == VOTE_UPHOLD || vote_choice == VOTE_OVERTURN, EUnauthorized);
        
        // Validate stake amount is within bounds
        assert!(stake_amount >= config.min_vote_stake && stake_amount <= config.max_vote_stake, EInvalidStakeAmount);
        
        // Verify voting period is active
        assert!(current_epoch >= dispute.voting_start_epoch, EVotingNotActive);
        assert!(current_epoch <= dispute.voting_end_epoch, EVotingEnded);
        
        // Verify voter hasn't already voted
        assert!(!table::contains(&dispute.voter_records, voter), EAlreadyVoted);
        
        // Record the vote
        let vote = Vote {
            voter,
            vote_choice,
            stake_amount,
            voted_at: current_epoch,
        };
        
        vector::push_back(&mut dispute.votes, vote);
        table::add(&mut dispute.voter_records, voter, true);
        
        // Update stake totals
        if (vote_choice == VOTE_UPHOLD) {
            dispute.uphold_stake = dispute.uphold_stake + stake_amount;
        } else {
            dispute.overturn_stake = dispute.overturn_stake + stake_amount;
        };
        
        // Take stake and hold it in the dispute
        let stake_balance = coin::into_balance(stake_coin);
        balance::join(&mut dispute.reward_pool, stake_balance);
        
        // Update registry tracking
        registry.total_votes_cast = registry.total_votes_cast + 1;
        
        // Emit vote event
        event::emit(DisputeVoteCastEvent {
            dispute_id: object::uid_to_address(&dispute.id),
            voter,
            vote_choice,
            stake_amount,
            total_uphold_stake: dispute.uphold_stake,
            total_overturn_stake: dispute.overturn_stake,
            timestamp,
        });
    }

    /// Resolve PoC dispute after voting period ends
    public entry fun resolve_dispute_voting(
        dispute: &mut PoCDispute,
        post: &mut social_contracts::post::Post,
        token_registry: &social_contracts::social_proof_tokens::TokenRegistry,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        let timestamp = tx_context::epoch_timestamp_ms(ctx);
        let dispute_id = object::uid_to_address(&dispute.id);
        
        // Verify voting period has ended
        assert!(current_epoch > dispute.voting_end_epoch, EVotingNotActive);
        
        // Verify there are votes to resolve
        assert!(vector::length(&dispute.votes) > 0, ENoVotesToResolve);
        
        // Determine winning side
        let winning_side = if (dispute.uphold_stake > dispute.overturn_stake) {
            VOTE_UPHOLD
        } else {
            VOTE_OVERTURN
        };
        
        let (total_winning_stake, total_losing_stake) = if (winning_side == VOTE_UPHOLD) {
            (dispute.uphold_stake, dispute.overturn_stake)
        } else {
            (dispute.overturn_stake, dispute.uphold_stake)
        };
        
        // Apply dispute resolution to post
        let (badge_revoked, redirection_removed) = if (winning_side == VOTE_OVERTURN) {
            // Challenger wins - clear PoC data
            social_contracts::post::clear_poc_data(post);
            (true, true)
        } else {
            // Original decision stands - no changes needed
            (false, false)
        };
        
        // Update dispute status
        dispute.status = if (winning_side == VOTE_UPHOLD) {
            DISPUTE_STATUS_RESOLVED_UPHELD
        } else {
            DISPUTE_STATUS_RESOLVED_OVERTURNED
        };
        
        // Emit resolution event
        event::emit(PoCDisputeResolvedEvent {
            dispute_id,
            post_id: dispute.post_id,
            resolution: dispute.status,
            winning_side,
            total_winning_stake,
            total_losing_stake,
            badge_revoked,
            redirection_removed,
            timestamp,
        });
        
        // Automatically update token pool if it exists
        update_token_pool_if_exists(token_registry, post, ctx);
    }

    /// Claim voting rewards after dispute resolution
    public entry fun claim_voting_reward(
        dispute: &mut PoCDispute,
        ctx: &mut TxContext
    ) {
        let claimer = tx_context::sender(ctx);
        let timestamp = tx_context::epoch_timestamp_ms(ctx);
        let dispute_id = object::uid_to_address(&dispute.id);
        
        // Verify dispute is resolved
        assert!(
            dispute.status == DISPUTE_STATUS_RESOLVED_UPHELD || 
            dispute.status == DISPUTE_STATUS_RESOLVED_OVERTURNED,
            EVotingNotActive
        );
        
        // Find the voter's vote and verify they voted on winning side
        let votes_len = vector::length(&dispute.votes);
        let mut vote_index = 0;
        let mut found_vote = false;
        let mut voter_stake = 0;
        let mut voter_choice = 0;
        
        while (vote_index < votes_len && !found_vote) {
            let vote = vector::borrow(&dispute.votes, vote_index);
            if (vote.voter == claimer) {
                found_vote = true;
                voter_stake = vote.stake_amount;
                voter_choice = vote.vote_choice;
            };
            vote_index = vote_index + 1;
        };
        
        assert!(found_vote, EUnauthorized);
        
        // Determine winning side and verify voter was on winning side
        let winning_side = if (dispute.uphold_stake > dispute.overturn_stake) {
            VOTE_UPHOLD
        } else {
            VOTE_OVERTURN
        };
        
        assert!(voter_choice == winning_side, EUnauthorized);
        
        // Calculate reward
        let (total_winning_stake, total_losing_stake) = if (winning_side == VOTE_UPHOLD) {
            (dispute.uphold_stake, dispute.overturn_stake)
        } else {
            (dispute.overturn_stake, dispute.uphold_stake)
        };
        
        // Calculate proportional reward: original stake + share of losing side
        let reward_from_losers = if (total_winning_stake > 0) {
            (((voter_stake as u128) * (total_losing_stake as u128)) / (total_winning_stake as u128)) as u64
        } else {
            0
        };
        
        let total_payout = voter_stake + reward_from_losers;
        
        // Verify sufficient balance in reward pool
        assert!(balance::value(&dispute.reward_pool) >= total_payout, EInsufficientFunds);
        
        // Transfer reward to voter
        let reward_coin = coin::from_balance(
            balance::split(&mut dispute.reward_pool, total_payout),
            ctx
        );
        transfer::public_transfer(reward_coin, claimer);
        
        // Emit reward event
        event::emit(VotingRewardClaimedEvent {
            dispute_id,
            voter: claimer,
            original_stake: voter_stake,
            reward_amount: reward_from_losers,
            total_payout,
            timestamp,
        });
    }

    // === Helper Functions ===

    /// Get similarity threshold for a media type
    fun get_threshold_for_media_type(config: &PoCConfig, media_type: u8): u64 {
        if (media_type == MEDIA_TYPE_IMAGE) {
            config.image_threshold
        } else if (media_type == MEDIA_TYPE_VIDEO) {
            config.video_threshold
        } else if (media_type == MEDIA_TYPE_AUDIO) {
            config.audio_threshold
        } else {
            abort EInvalidMediaType
        }
    }

    // === Public Getter Functions ===

    /// Check if an address is the authorized oracle
    public fun is_authorized_oracle(config: &PoCConfig, caller: address): bool {
        caller == config.oracle_address
    }

    /// Get registry statistics
    public fun get_registry_stats(registry: &PoCRegistry): (u64, u64, u64, u64) {
        (
            registry.total_badges_issued,
            registry.total_redirections_created,
            registry.total_disputes_submitted,
            registry.total_votes_cast
        )
    }

    /// Check if a post has PoC data that can be disputed
    public fun has_poc_data(post: &social_contracts::post::Post): bool {
        option::is_some(social_contracts::post::get_poc_badge_id(post)) ||
        option::is_some(social_contracts::post::get_revenue_redirect_to(post))
    }

    /// Get dispute voting status
    public fun get_dispute_voting_status(dispute: &PoCDispute, current_epoch: u64): (bool, bool, u8) {
        let voting_active = current_epoch >= dispute.voting_start_epoch && current_epoch <= dispute.voting_end_epoch;
        let voting_ended = current_epoch > dispute.voting_end_epoch;
        (voting_active, voting_ended, dispute.status)
    }

    /// Get dispute stake totals
    public fun get_dispute_stakes(dispute: &PoCDispute): (u64, u64, u64) {
        (dispute.uphold_stake, dispute.overturn_stake, vector::length(&dispute.votes))
    }

    /// Check if user has already voted on dispute
    public fun has_user_voted(dispute: &PoCDispute, user: address): bool {
        table::contains(&dispute.voter_records, user)
    }

    // === Versioning Functions ===

    /// Get the version of the PoC config
    public fun config_version(config: &PoCConfig): u64 {
        config.version
    }

    /// Get the version of a PoC dispute
    public fun dispute_version(dispute: &PoCDispute): u64 {
        dispute.version
    }

    /// Get the version of the PoC registry
    public fun registry_version(registry: &PoCRegistry): u64 {
        registry.version
    }

    /// Migration function for PoCConfig
    public entry fun migrate_poc_config(
        config: &mut PoCConfig,
        _: &UpgradeAdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        
        // Verify this is an upgrade
        assert!(config.version < current_version, EWrongVersion);
        
        // Remember old version and update to new version
        let old_version = config.version;
        config.version = current_version;
        
        // Emit event for object migration
        let config_id = object::id(config);
        upgrade::emit_migration_event(
            config_id,
            string::utf8(b"PoCConfig"),
            old_version,
            tx_context::sender(ctx)
        );
    }

    /// Migration function for PoCDispute
    public entry fun migrate_poc_dispute(
        dispute: &mut PoCDispute,
        _: &UpgradeAdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        
        // Verify this is an upgrade
        assert!(dispute.version < current_version, EWrongVersion);
        
        // Remember old version and update to new version
        let old_version = dispute.version;
        dispute.version = current_version;
        
        // Emit event for object migration
        let dispute_id = object::id(dispute);
        upgrade::emit_migration_event(
            dispute_id,
            string::utf8(b"PoCDispute"),
            old_version,
            tx_context::sender(ctx)
        );
    }

    /// Migration function for PoCRegistry
    public entry fun migrate_poc_registry(
        registry: &mut PoCRegistry,
        _: &UpgradeAdminCap,
        ctx: &mut TxContext
    ) {
        let current_version = upgrade::current_version();
        
        // Verify this is an upgrade
        assert!(registry.version < current_version, EWrongVersion);
        
        // Remember old version and update to new version
        let old_version = registry.version;
        registry.version = current_version;
        
        // Emit event for object migration
        let registry_id = object::id(registry);
        upgrade::emit_migration_event(
            registry_id,
            string::utf8(b"PoCRegistry"),
            old_version,
            tx_context::sender(ctx)
        );
    }

    /// Create a PoCAdminCap for bootstrap (package visibility only)
    /// This function is only callable by other modules in the same package
    public(package) fun create_poc_admin_cap(ctx: &mut TxContext): PoCAdminCap {
        PoCAdminCap {
            id: object::new(ctx)
        }
    }

    // === Test-only functions ===

    #[test_only]
    /// Initialize the PoC system for testing
    public fun test_init(ctx: &mut TxContext) {
        bootstrap_init(ctx)
    }
} 