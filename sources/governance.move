// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

/// Governance module for the MySocial network
/// Manages the decentralized governance system with delegate council and community assembly
/// Implements proposal submission, voting, and execution processes

module social_contracts::governance {
    use std::string::{String};
    
    use mys::dynamic_field;
    use mys::vec_set::{Self, VecSet};
    use mys::event;
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::balance::{Self, Balance};
    use mys::mys::MYS;
    use mys::package::{Self, Publisher};
    
    use social_contracts::upgrade;
    use social_contracts::profile;

    /// Error codes
    const EUnauthorized: u64 = 0;
    const EInvalidAmount: u64 = 1;
    const EInvalidParameter: u64 = 2;
    const ENotDelegate: u64 = 3;
    const EAlreadyDelegate: u64 = 4;
    const EProposalNotFound: u64 = 6;
    const EInvalidProposalStatus: u64 = 7;
    const EAlreadyVoted: u64 = 8;
    const ENotVotingPhase: u64 = 9;
    const EVotingPeriodNotEnded: u64 = 11;
    const EVotingPeriodEnded: u64 = 12;
    const EExceedsMaxVotes: u64 = 13;
    const EInvalidVoteCount: u64 = 14;
    const EInvalidRegistry: u64 = 15;
    const EAlreadyNominated: u64 = 16;
    const EWrongVersion: u64 = 17;

    /// Proposal type constants
    const PROPOSAL_TYPE_ECOSYSTEM: u8 = 0;
    const PROPOSAL_TYPE_REPUTATION: u8 = 1;
    const PROPOSAL_TYPE_COMMUNITY_NOTES: u8 = 2;
    const PROPOSAL_TYPE_PLATFORM: u8 = 3;

    /// Proposal status constants
    const STATUS_SUBMITTED: u8 = 0;
    const STATUS_DELEGATE_REVIEW: u8 = 1;
    const STATUS_COMMUNITY_VOTING: u8 = 2;
    const STATUS_APPROVED: u8 = 3;
    const STATUS_REJECTED: u8 = 4;
    const STATUS_IMPLEMENTED: u8 = 5;
    const STATUS_OWNER_RESCIND: u8 = 6;

    /// Field names for dynamic fields
    const VOTED_COMMUNITY_FIELD: vector<u8> = b"voted_community";
    const DELEGATE_VOTES_FIELD: vector<u8> = b"delegate_votes";
    const VOTED_FOR_FIELD: vector<u8> = b"voted_for";
    const VOTED_AGAINST_FIELD: vector<u8> = b"voted_against";
    const VOTED_DELEGATES_LIST_FIELD: vector<u8> = b"voted_delegates_list";
    const DELEGATE_REASONS_FIELD: vector<u8> = b"delegate_reasons";

    /// Governance registry that keeps track of all delegates and proposals
    public struct GovernanceDAO has key {
        id: UID,
        /// Registry type identifier (ecosystem, reputation, community notes)
        registry_type: u8,
        /// Configuration parameters
        delegate_count: u64,
        delegate_term_epochs: u64,
        proposal_submission_cost: u64,
        min_on_chain_age_days: u64,
        max_votes_per_user: u64,
        quadratic_base_cost: u64,
        voting_period_epochs: u64,  // Number of epochs for the voting period
        quorum_votes: u64,  // Minimum number of votes required for a valid proposal outcome
        /// Tables and mappings
        delegates: Table<address, Delegate>,
        proposals: Table<ID, Proposal>,
        proposals_by_status: Table<u8, vector<ID>>,
        treasury: Balance<MYS>, /// Treasury for proposal costs and rewards
        nominated_delegates: Table<address, NominatedDelegate>,
        delegate_addresses: VecSet<address>,
        nominee_addresses: VecSet<address>,
        voters: Table<address, Table<address, bool>>, // target -> (voter -> upvote)
        version: u64,
    }

    /// Delegate struct representing a member of the delegate council
    public struct Delegate has store {
        address: address,
        profile_id: ID,
        upvotes: u64,
        downvotes: u64,
        proposals_reviewed: u64,
        proposals_submitted: u64,
        sided_winning_proposals: u64,  // Number of proposals where delegate voted with the winning side
        sided_losing_proposals: u64,   // Number of proposals where delegate voted with the losing side
        term_start: u64,  // Epoch when term started
        term_end: u64,    // Epoch when term ends
    }

    /// Nominee struct representing a user nominated but not yet active
    public struct NominatedDelegate has store {
        address: address,
        profile_id: ID,
        scheduled_term_start_epoch: u64,
        upvotes: u64,
        downvotes: u64,
    }

    /// Proposal struct representing a governance proposal
    public struct Proposal has key, store {
        id: UID,
        title: String,
        description: String,
        proposal_type: u8,  // Ecosystem, Reputation, Community Notes
        reference_id: Option<ID>,  // Optional reference to content/profile/post ID
        metadata_json: Option<String>, // Optional JSON metadata string
        submitter: address,
        submission_time: u64,
        delegate_approval_count: u64,
        delegate_rejection_count: u64,
        community_votes_for: u64,
        community_votes_against: u64,
        status: u8,  // Submitted, DelegateReview, CommunityVoting, Approved, Rejected, Implemented
        voting_start_time: u64,
        voting_end_time: u64,
        reward_pool: Balance<MYS>,
    }

    /// Vote struct for tracking individual votes - unused fields removed
    public struct Vote has store, drop {}

    /// Event emitted when a new delegate is elected
    public struct DelegateElectedEvent has copy, drop {
        delegate_address: address,
        profile_id: ID,
        term_start: u64,
        term_end: u64,
        registry_type: u8,
    }

    /// Event emitted when a user is nominated to become a delegate in a future term
    public struct DelegateNominatedEvent has copy, drop {
        nominee_address: address,
        profile_id: ID,
        scheduled_term_start_epoch: u64,
        registry_type: u8,
    }

    /// Event emitted when a delegate or nominee is voted for/against
    public struct DelegateVotedEvent has copy, drop {
        target_address: address,
        voter: address,
        is_active_delegate: bool,
        upvote: bool,
        new_upvote_count: u64,
        new_downvote_count: u64,
        registry_type: u8,
    }

    /// Event emitted when a proposal is submitted
    public struct ProposalSubmittedEvent has copy, drop {
        proposal_id: ID,
        title: String,
        description: String,
        proposal_type: u8,
        reference_id: Option<ID>,
        metadata_json: Option<String>,
        submitter: address,
        reward_amount: u64,
        submission_time: u64,
    }

    /// Event emitted when a delegate votes on a proposal
    public struct DelegateVoteEvent has copy, drop {
        proposal_id: ID,
        delegate_address: address,
        approve: bool,
        vote_time: u64,
        reason: Option<String>,
    }

    /// Event emitted when a community member votes on a proposal
    public struct CommunityVoteEvent has copy, drop {
        proposal_id: ID,
        voter: address,
        vote_weight: u64,
        approve: bool,
        vote_time: u64,
        vote_cost: u64,
    }

    /// Event emitted when a proposal is approved by the delegate council
    public struct ProposalApprovedForVotingEvent has copy, drop {
        proposal_id: ID,
        voting_start_time: u64,
        voting_end_time: u64,
    }

    /// Event emitted when a proposal is rejected by the delegate council
    public struct ProposalRejectedEvent has copy, drop {
        proposal_id: ID,
        rejection_time: u64,
    }

    /// Event emitted when a proposal is approved by the community
    public struct ProposalApprovedEvent has copy, drop {
        proposal_id: ID,
        approval_time: u64,
        votes_for: u64,
        votes_against: u64,
    }

    /// Event emitted when a proposal is rejected by the community
    public struct ProposalRejectedByCommunityEvent has copy, drop {
        proposal_id: ID,
        rejection_time: u64,
        votes_for: u64,
        votes_against: u64,
    }

    /// Event emitted when a proposal is implemented
    public struct ProposalImplementedEvent has copy, drop {
        proposal_id: ID,
        implementation_time: u64,
        description: Option<String>,
    }

    /// Event emitted when rewards are distributed to voters
    public struct RewardsDistributedEvent has copy, drop {
        proposal_id: ID,
        total_reward: u64,
        recipient_count: u64,
        distribution_time: u64,
    }

    /// Event emitted when a proposal is rescinded by its submitter
    public struct ProposalRescindedEvent has copy, drop {
        proposal_id: ID,
        submitter: address,
        rescind_time: u64,
        refund_amount: u64,
    }

    /// Create and share separate governance registries for each proposal type
    fun init(ctx: &mut TxContext) {
        // Create Ecosystem Governance Registry
        let mut ecosystem_registry = GovernanceDAO {
            id: object::new(ctx),
            registry_type: PROPOSAL_TYPE_ECOSYSTEM,
            // Configuration parameters specific to ecosystem governance
            delegate_count: 3, // Larger council for ecosystem decisions
            delegate_term_epochs: 90, // 3 months for ecosystem delegates
            proposal_submission_cost: 100_000_000, // 100 MYS for ecosystem proposals
            min_on_chain_age_days: 30, // 1 month minimum for ecosystem voting
            max_votes_per_user: 10, // Up to 10 votes per user
            quadratic_base_cost: 10_000_000, // 10 MYS per additional vote
            voting_period_epochs: 7, // 7 epochs for ecosystem votes
            quorum_votes: 20, // 20 votes required for ecosystem proposals
            // Tables
            delegates: table::new<address, Delegate>(ctx),
            proposals: table::new<ID, Proposal>(ctx),
            proposals_by_status: table::new<u8, vector<ID>>(ctx),
            treasury: balance::zero(),
            nominated_delegates: table::new<address, NominatedDelegate>(ctx),
            delegate_addresses: vec_set::empty<address>(),
            nominee_addresses: vec_set::empty<address>(),
            voters: table::new<address, Table<address, bool>>(ctx),
            version: upgrade::current_version(),
        };
        
        // Create Reputation Governance Registry
        let mut reputation_registry = GovernanceDAO {
            id: object::new(ctx),
            registry_type: PROPOSAL_TYPE_REPUTATION,
            // Configuration parameters specific to reputation governance
            delegate_count: 5, // Smaller council for reputation disputes
            delegate_term_epochs: 60, // 2 months for reputation delegates
            proposal_submission_cost: 50_000_000, // 50 MYS for reputation disputes
            min_on_chain_age_days: 7, // 1 week minimum for reputation voting
            max_votes_per_user: 5, // Up to 5 votes per user
            quadratic_base_cost: 5_000_000, // 5 MYS per additional vote
            voting_period_epochs: 3, // 3 epochs for reputation votes
            quorum_votes: 15, // 15 votes required for reputation proposals
            // Tables
            delegates: table::new<address, Delegate>(ctx),
            proposals: table::new<ID, Proposal>(ctx),
            proposals_by_status: table::new<u8, vector<ID>>(ctx),
            treasury: balance::zero(),
            nominated_delegates: table::new<address, NominatedDelegate>(ctx),
            delegate_addresses: vec_set::empty<address>(),
            nominee_addresses: vec_set::empty<address>(),
            voters: table::new<address, Table<address, bool>>(ctx),
            version: upgrade::current_version(),
        };
        
        // Create Community Notes Governance Registry
        let mut community_notes_registry = GovernanceDAO {
            id: object::new(ctx),
            registry_type: PROPOSAL_TYPE_COMMUNITY_NOTES,
            // Configuration parameters specific to community notes governance
            delegate_count: 7, // Medium council for community notes
            delegate_term_epochs: 30, // 1 month for community notes delegates
            proposal_submission_cost: 25_000_000, // 25 MYS for community notes
            min_on_chain_age_days: 3, // 3 days minimum for community notes voting
            max_votes_per_user: 3, // Up to 3 votes per user
            quadratic_base_cost: 2_500_000, // 2.5 MYS per additional vote
            voting_period_epochs: 1, // 1 epoch for community notes votes
            quorum_votes: 10, // 10 votes required for community notes proposals
            // Tables
            delegates: table::new<address, Delegate>(ctx),
            proposals: table::new<ID, Proposal>(ctx),
            proposals_by_status: table::new<u8, vector<ID>>(ctx),
            treasury: balance::zero(),
            nominated_delegates: table::new<address, NominatedDelegate>(ctx),
            delegate_addresses: vec_set::empty<address>(),
            nominee_addresses: vec_set::empty<address>(),
            voters: table::new<address, Table<address, bool>>(ctx),
            version: upgrade::current_version(),
        };
        
        // Initialize each registry's status tables
        initialize_registry_tables(&mut ecosystem_registry, ctx);
        initialize_registry_tables(&mut reputation_registry, ctx);
        initialize_registry_tables(&mut community_notes_registry, ctx);
        
        // Share the registry objects
        transfer::share_object(ecosystem_registry);
        transfer::share_object(reputation_registry);
        transfer::share_object(community_notes_registry);
    }

    fun initialize_registry_tables(registry: &mut GovernanceDAO, _ctx: &mut TxContext) {
        table::add(&mut registry.proposals_by_status, STATUS_SUBMITTED, vector::empty<ID>());
        table::add(&mut registry.proposals_by_status, STATUS_DELEGATE_REVIEW, vector::empty<ID>());
        table::add(&mut registry.proposals_by_status, STATUS_COMMUNITY_VOTING, vector::empty<ID>());
        table::add(&mut registry.proposals_by_status, STATUS_APPROVED, vector::empty<ID>());
        table::add(&mut registry.proposals_by_status, STATUS_REJECTED, vector::empty<ID>());
        table::add(&mut registry.proposals_by_status, STATUS_IMPLEMENTED, vector::empty<ID>());
        table::add(&mut registry.proposals_by_status, STATUS_OWNER_RESCIND, vector::empty<ID>());
    }

    /// Update governance parameters
    /// Can only be called by the contract owner with a valid publisher
    public entry fun update_governance_parameters(
        registry: &mut GovernanceDAO,
        publisher: &Publisher,
        delegate_count: u64,
        delegate_term_epochs: u64,
        proposal_submission_cost: u64,
        min_on_chain_age_days: u64,
        max_votes_per_user: u64,
        quadratic_base_cost: u64,
        voting_period_epochs: u64,
        quorum_votes: u64,
        _ctx: &mut TxContext
    ) {
        // Verify caller has a valid publisher for this module
        assert!(package::from_module<GovernanceDAO>(publisher), EUnauthorized);
        // Ensure parameters are sensible
        assert!(delegate_count > 1, EInvalidParameter);
        assert!(delegate_term_epochs > 0, EInvalidParameter);
        // proposal_submission_cost can be 0
        // min_on_chain_age_days can be 0
        assert!(max_votes_per_user > 0, EInvalidParameter);
        // quadratic_base_cost can be 0 (if voting is free)
        assert!(voting_period_epochs > 0, EInvalidParameter);
        assert!(quorum_votes > 0, EInvalidParameter);
        
        // Update parameters
        registry.delegate_count = delegate_count;
        registry.delegate_term_epochs = delegate_term_epochs;
        registry.proposal_submission_cost = proposal_submission_cost;
        registry.min_on_chain_age_days = min_on_chain_age_days;
        registry.max_votes_per_user = max_votes_per_user;
        registry.quadratic_base_cost = quadratic_base_cost;
        registry.voting_period_epochs = voting_period_epochs;
        registry.quorum_votes = quorum_votes;
    }

    /// Nominate self as a delegate
    /// Requires the caller to have a valid profile
    public entry fun nominate_delegate(
        registry: &mut GovernanceDAO,
        profile_registry: &profile::UsernameRegistry,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let current_epoch = tx_context::epoch(ctx);
        
        // Check if already a delegate or nominee delegate
        assert!(!table::contains(&registry.delegates, caller), EAlreadyDelegate);
        assert!(!table::contains(&registry.nominated_delegates, caller), EAlreadyNominated);

        let mut profile_id_opt = profile::lookup_profile_by_owner(profile_registry, caller);
        assert!(option::is_some(&profile_id_opt), EUnauthorized);
        
        // Get profile ID
        let profile_id_addr = option::extract(&mut profile_id_opt);
        let profile_id = object::id_from_address(profile_id_addr);

        let scheduled_term_start_epoch = ((current_epoch / registry.delegate_term_epochs) + 1) * registry.delegate_term_epochs;

        let nominated_delegate = NominatedDelegate {
            address: caller,
            profile_id,
            scheduled_term_start_epoch,
            upvotes: 0,
            downvotes: 0,
        };
        table::add(&mut registry.nominated_delegates, caller, nominated_delegate);
        vec_set::insert(&mut registry.nominee_addresses, caller);

        // Initialize voter tracking table for this nominee
        table::add(&mut registry.voters, caller, table::new<address, bool>(ctx));

        event::emit(DelegateNominatedEvent {
            nominee_address: caller,
            profile_id,
            scheduled_term_start_epoch,
            registry_type: registry.registry_type,
        });
    }

    /// Vote for or against a delegate or nominee delegate
    /// Positive votes support the delegate, negative votes express disapproval
    /// Users can change their vote at any time
    public entry fun vote_for_delegate(
        registry: &mut GovernanceDAO,
        target_address: address,
        upvote: bool,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        
        // Don't allow self-voting
        assert!(caller != target_address, EUnauthorized);
        
        // Variables for event emission
        let is_active_delegate: bool;
        let upvote_count: u64;
        let downvote_count: u64;
        
        // Handle voting for active delegates
        if (table::contains(&registry.delegates, target_address)) {
            is_active_delegate = true;
            let delegate = table::borrow_mut(&mut registry.delegates, target_address);
            
            // Create voter table for this target if it doesn't exist
            if (!table::contains(&registry.voters, target_address)) {
                table::add(&mut registry.voters, target_address, table::new<address, bool>(ctx));
            };
            
            let voter_table = table::borrow_mut(&mut registry.voters, target_address);
            
            // Check if user has already voted
            if (table::contains(voter_table, caller)) {
                let previous_vote = *table::borrow(voter_table, caller);
                
                // If same vote, do nothing
                if (previous_vote == upvote) {
                    return
                };
                
                // Different vote - remove previous vote
                if (previous_vote) {
                    delegate.upvotes = delegate.upvotes - 1;
                } else {
                    delegate.downvotes = delegate.downvotes - 1;
                };
                
                // Add new vote
                if (upvote) {
                    delegate.upvotes = delegate.upvotes + 1;
                } else {
                    delegate.downvotes = delegate.downvotes + 1;
                };
                
                // Update record
                *table::borrow_mut(voter_table, caller) = upvote;
            } else {
                // First time voting for this target
                if (upvote) {
                    delegate.upvotes = delegate.upvotes + 1;
                } else {
                    delegate.downvotes = delegate.downvotes + 1;
                };
                
                // Record vote
                table::add(voter_table, caller, upvote);
            };
            
            upvote_count = delegate.upvotes;
            downvote_count = delegate.downvotes;
        }
        // Handle voting for nominee delegates
        else if (table::contains(&registry.nominated_delegates, target_address)) {
            is_active_delegate = false;
            let nominee = table::borrow_mut(&mut registry.nominated_delegates, target_address);
            
            // Create voter table for this target if it doesn't exist
            if (!table::contains(&registry.voters, target_address)) {
                table::add(&mut registry.voters, target_address, table::new<address, bool>(ctx));
            };
            
            let voter_table = table::borrow_mut(&mut registry.voters, target_address);
            
            // Check if user has already voted
            if (table::contains(voter_table, caller)) {
                let previous_vote = *table::borrow(voter_table, caller);
                
                // If same vote, do nothing
                if (previous_vote == upvote) {
                    return
                };
                
                // Different vote - remove previous vote
                if (previous_vote) {
                    nominee.upvotes = nominee.upvotes - 1;
                } else {
                    nominee.downvotes = nominee.downvotes - 1;
                };
                
                // Add new vote
                if (upvote) {
                    nominee.upvotes = nominee.upvotes + 1;
                } else {
                    nominee.downvotes = nominee.downvotes + 1;
                };
                
                // Update record
                *table::borrow_mut(voter_table, caller) = upvote;
            } else {
                // First time voting for this nominee
                if (upvote) {
                    nominee.upvotes = nominee.upvotes + 1;
                } else {
                    nominee.downvotes = nominee.downvotes + 1;
                };
                
                // Record vote
                table::add(voter_table, caller, upvote);
            };
            
            upvote_count = nominee.upvotes;
            downvote_count = nominee.downvotes;
        }
        else { abort ENotDelegate };
        
        event::emit(DelegateVotedEvent {
            target_address,
            voter: caller,
            is_active_delegate,
            upvote,
            new_upvote_count: upvote_count,
            new_downvote_count: downvote_count,
            registry_type: registry.registry_type,
        });
    }

    /// Updates delegate panel at the end of a delegate term cycle.
    public entry fun update_delegate_panel(
        registry: &mut GovernanceDAO,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        let delegate_term_epochs = registry.delegate_term_epochs;
        assert!(delegate_term_epochs > 0, EInvalidParameter);

        if (current_epoch == 0 || current_epoch % delegate_term_epochs != 0) {
            return
        };

        // --- Gather Candidates Data --- 
        let mut candidate_addresses = vector::empty<address>();
        let mut candidate_profile_ids = vector::empty<ID>();
        let mut candidate_upvotes = vector::empty<u64>();
        let mut candidate_downvotes = vector::empty<u64>();
        let mut candidate_net_votes = vector::empty<u64>(); // For sorting calculations
        let mut candidate_is_incumbent = vector::empty<bool>(); // Track incumbent status for tie-breaking

        // Use 1000 as the baseline score where upvotes and downvotes are equal
        let baseline_score: u64 = 1000;

        // 1. Gather Active Delegates (using the tracking set)
        let active_delegate_keys_vec = vec_set::into_keys(registry.delegate_addresses); // Consumes the set
        let len_active = vector::length(&active_delegate_keys_vec);
        
        let mut i = 0;
        while (i < len_active) {
            let addr = *vector::borrow(&active_delegate_keys_vec, i);
            // Need to borrow from the actual table to get full data
            if (table::contains(&registry.delegates, addr)) { // Check existence before borrow
                let delegate: &Delegate = table::borrow(&registry.delegates, addr);
                vector::push_back(&mut candidate_addresses, addr);
                vector::push_back(&mut candidate_profile_ids, delegate.profile_id);
                vector::push_back(&mut candidate_upvotes, delegate.upvotes);
                vector::push_back(&mut candidate_downvotes, delegate.downvotes);
                vector::push_back(&mut candidate_is_incumbent, true); // Mark as incumbent
                
                // Calculate net votes with baseline offset (allows negative effective scores)
                let net_votes = if (delegate.upvotes >= delegate.downvotes) {
                    // If more upvotes than downvotes, add the difference to baseline
                    baseline_score + (delegate.upvotes - delegate.downvotes)
                } else {
                    // If more downvotes than upvotes, subtract the difference from baseline
                    // But make sure we don't underflow
                    if (delegate.downvotes - delegate.upvotes >= baseline_score) {
                        0 // Minimum score
                    } else {
                        baseline_score - (delegate.downvotes - delegate.upvotes)
                    }
                };
                
                vector::push_back(&mut candidate_net_votes, net_votes);
            };
            // Note: If delegate wasn't found in table (somehow desynced), it's skipped.
            i = i + 1;
        };
        // Recreate the delegate_addresses set as empty, it will be repopulated with winners
        registry.delegate_addresses = vec_set::empty<address>();

        // 2. Gather Nominated Delegates (using the tracking set)
        let nominee_keys_vec = vec_set::into_keys(registry.nominee_addresses); // Consumes the set
        let len_nominated = vector::length(&nominee_keys_vec);
        
        let mut j = 0;
        while (j < len_nominated) {
            let addr = *vector::borrow(&nominee_keys_vec, j);
            // Check if it was already added as an active delegate (shouldn't happen if sets are correct)
            // We can skip this check if we ensure sets are managed correctly.
            // Need to borrow from the actual table to get full data
            if (table::contains(&registry.nominated_delegates, addr)) { // Check existence
                let nominee: &NominatedDelegate = table::borrow(&registry.nominated_delegates, addr);
                vector::push_back(&mut candidate_addresses, addr);
                vector::push_back(&mut candidate_profile_ids, nominee.profile_id);
                vector::push_back(&mut candidate_upvotes, nominee.upvotes);
                vector::push_back(&mut candidate_downvotes, nominee.downvotes);
                vector::push_back(&mut candidate_is_incumbent, false); // Mark as non-incumbent
                
                // Calculate net votes with baseline offset (allows negative effective scores)
                let net_votes = if (nominee.upvotes >= nominee.downvotes) {
                    // If more upvotes than downvotes, add the difference to baseline
                    baseline_score + (nominee.upvotes - nominee.downvotes)
                } else {
                    // If more downvotes than upvotes, subtract the difference from baseline
                    // But make sure we don't underflow
                    if (nominee.downvotes - nominee.upvotes >= baseline_score) {
                        0 // Minimum score
                    } else {
                        baseline_score - (nominee.downvotes - nominee.upvotes)
                    }
                };
                
                vector::push_back(&mut candidate_net_votes, net_votes);
            };
            j = j + 1;
        };
        // Recreate the nominee_addresses set as empty, losers will not be re-added.
        registry.nominee_addresses = vec_set::empty<address>();

        // --- Sort Candidate Data by net votes (higher is better) --- 
        let candidate_count = vector::length(&candidate_addresses);
        let mut a = 0;
        while (a < candidate_count) {
            let mut b = a + 1;
            while (b < candidate_count) {
                // Compare net votes
                let a_votes = *vector::borrow(&candidate_net_votes, a);
                let b_votes = *vector::borrow(&candidate_net_votes, b);
                
                // If b has more net votes than a, or they're tied but b is an incumbent and a is not, swap them
                let should_swap = if (b_votes > a_votes) {
                    true
                } else if (b_votes == a_votes) {
                    // Tie-breaking: prefer incumbent delegates
                    let a_incumbent = *vector::borrow(&candidate_is_incumbent, a);
                    let b_incumbent = *vector::borrow(&candidate_is_incumbent, b);
                    
                    // Only swap if b is incumbent and a is not
                    b_incumbent && !a_incumbent
                } else {
                    false
                };
                
                if (should_swap) {
                    // Swap addresses
                    let temp_addr = *vector::borrow(&candidate_addresses, a);
                    *vector::borrow_mut(&mut candidate_addresses, a) = *vector::borrow(&candidate_addresses, b);
                    *vector::borrow_mut(&mut candidate_addresses, b) = temp_addr;
                    
                    // Swap profile IDs
                    let temp_id = *vector::borrow(&candidate_profile_ids, a);
                    *vector::borrow_mut(&mut candidate_profile_ids, a) = *vector::borrow(&candidate_profile_ids, b);
                    *vector::borrow_mut(&mut candidate_profile_ids, b) = temp_id;
                    
                    // Swap upvotes
                    let temp_up = *vector::borrow(&candidate_upvotes, a);
                    *vector::borrow_mut(&mut candidate_upvotes, a) = *vector::borrow(&candidate_upvotes, b);
                    *vector::borrow_mut(&mut candidate_upvotes, b) = temp_up;
                    
                    // Swap downvotes
                    let temp_down = *vector::borrow(&candidate_downvotes, a);
                    *vector::borrow_mut(&mut candidate_downvotes, a) = *vector::borrow(&candidate_downvotes, b);
                    *vector::borrow_mut(&mut candidate_downvotes, b) = temp_down;
                    
                    // Swap net votes
                    let temp_net = *vector::borrow(&candidate_net_votes, a);
                    *vector::borrow_mut(&mut candidate_net_votes, a) = *vector::borrow(&candidate_net_votes, b);
                    *vector::borrow_mut(&mut candidate_net_votes, b) = temp_net;
                    
                    // Swap incumbent status
                    let temp_inc = *vector::borrow(&candidate_is_incumbent, a);
                    *vector::borrow_mut(&mut candidate_is_incumbent, a) = *vector::borrow(&candidate_is_incumbent, b);
                    *vector::borrow_mut(&mut candidate_is_incumbent, b) = temp_inc;
                };
                b = b + 1;
            };
            a = a + 1;
        };

        // --- Select Winners and Update State --- 
        let num_winners_to_select = registry.delegate_count;
        let actual_candidate_count = vector::length(&candidate_addresses);
        let final_winner_count = if (actual_candidate_count < num_winners_to_select) { actual_candidate_count } else { num_winners_to_select };

        // --- Cleanup Old State --- 
        // 1. Remove *all* previously active delegates from the table
        // We iterate using the keys vector we got earlier
        let mut k = 0;
        while (k < len_active) {
            let addr = *vector::borrow(&active_delegate_keys_vec, k);
            // Check if it exists before removing (might have been removed if somehow duplicated)
            if (table::contains(&registry.delegates, addr)) {
                 let old_delegate = table::remove(&mut registry.delegates, addr);
                 let Delegate { address: _, profile_id: _, upvotes: _, downvotes: _, proposals_reviewed: _, proposals_submitted: _, sided_winning_proposals: _, sided_losing_proposals: _, term_start: _, term_end: _ } = old_delegate;
            };
            k = k + 1;
        };

        // 2. Remove *all* previously nominated delegates from the table
        let mut l = 0;
        while (l < len_nominated) {
            let addr = *vector::borrow(&nominee_keys_vec, l);
            if (table::contains(&registry.nominated_delegates, addr)) { 
                let old_nominee = table::remove(&mut registry.nominated_delegates, addr);
                let NominatedDelegate { address: _, profile_id: _, scheduled_term_start_epoch: _, upvotes: _, downvotes: _ } = old_nominee;
             };
             l = l + 1;
        };

        // --- Add Winners to the Delegates Table --- 
        // The delegates table should now be empty. Add the winners.
        let mut m = 0;
        while (m < final_winner_count) {
            let winner_addr = *vector::borrow(&candidate_addresses, m);
            let winner_profile_id = *vector::borrow(&candidate_profile_ids, m);
            let winner_upvotes = *vector::borrow(&candidate_upvotes, m);
            let winner_downvotes = *vector::borrow(&candidate_downvotes, m);
            
            let term_start = current_epoch;
            let term_end = term_start + delegate_term_epochs;

            let new_delegate = Delegate {
                address: winner_addr,
                profile_id: winner_profile_id,
                upvotes: winner_upvotes,
                downvotes: winner_downvotes,
                proposals_reviewed: 0, // Reset counters
                proposals_submitted: 0,
                sided_winning_proposals: 0,
                sided_losing_proposals: 0,
                term_start: term_start,
                term_end: term_end,
            };
            // Add winner to the (previously emptied) delegates table
            table::add(&mut registry.delegates, winner_addr, new_delegate);
            // Add winner's address back to the tracking set
            vec_set::insert(&mut registry.delegate_addresses, winner_addr);

            event::emit(DelegateElectedEvent {
                delegate_address: winner_addr,
                profile_id: winner_profile_id,
                term_start: term_start,
                term_end: term_end,
                registry_type: registry.registry_type,
            });
            m = m + 1;
        };
        
        // Destroy helper vectors used for candidate data
        vector::destroy_empty(candidate_addresses);
        vector::destroy_empty(candidate_profile_ids);
        vector::destroy_empty(candidate_upvotes);
        vector::destroy_empty(candidate_downvotes);
        vector::destroy_empty(candidate_net_votes);
        vector::destroy_empty(candidate_is_incumbent);
        // Destroy key vectors obtained from into_keys
        vector::destroy_empty(active_delegate_keys_vec);
        vector::destroy_empty(nominee_keys_vec);
    }

    /// Universal function to submit any type of proposal
    /// Handles all proposal types: ecosystem, reputation disputes, and community notes
    public entry fun submit_proposal(
        registry: &mut GovernanceDAO,
        proposal_type: u8,
        title: String,
        description: String,
        disputed_id: Option<ID>, // Optional ID for disputes (profile or content)
        reference_id: Option<ID>, // Optional reference
        metadata_json: Option<String>,
        coin: &mut Coin<MYS>,
        ctx: &mut TxContext
    ) {
        // Verify proposal type is valid
        assert!(proposal_type <= PROPOSAL_TYPE_PLATFORM, EInvalidParameter);
        
        // Verify registry type matches proposal type
        assert!(registry.registry_type == proposal_type, EInvalidRegistry);
        
        // Handle reference ID based on proposal type
        let actual_reference_id = if (proposal_type == PROPOSAL_TYPE_ECOSYSTEM) {
            // Ecosystem proposals use reference_id as provided
            reference_id
        } else if (option::is_some(&reference_id)) {
            // If reference_id is explicitly provided, use it for any proposal type
            reference_id
        } else if (option::is_some(&disputed_id)) {
            // For disputes (reputation or community notes), use disputed_id as the reference if no reference provided
            disputed_id
        } else {
            // For disputes, a reference or disputed ID should be provided
            if (proposal_type != PROPOSAL_TYPE_ECOSYSTEM) {
                // Reputation and community notes should have a reference
                assert!(false, EInvalidParameter);
            };
            option::none<ID>()
        };
        
        // Submit the proposal using the internal implementation
        submit_proposal_internal(
            registry,
            title,
            description,
            proposal_type,
            actual_reference_id,
            metadata_json,
            coin,
            ctx
        );
    }

    /// Submit a new proposal to the ecosystem registry
    /// Requires staking MYS tokens equal to the proposal submission cost
    public entry fun submit_ecosystem_proposal(
        registry: &mut GovernanceDAO,
        title: String,
        description: String,
        reference_id: Option<ID>,
        metadata_json: Option<String>,
        coin: &mut Coin<MYS>,
        ctx: &mut TxContext
    ) {
        submit_proposal(
            registry,
            PROPOSAL_TYPE_ECOSYSTEM,
            title,
            description,
            option::none<ID>(), // No disputed ID for ecosystem proposals
            reference_id,
            metadata_json,
            coin,
            ctx
        );
    }

    /// Submit a special proposal for reputation dispute
    public entry fun submit_reputation_dispute(
        registry: &mut GovernanceDAO,
        title: String,
        description: String,
        disputed_profile_id: ID,
        reference_id: Option<ID>,
        metadata_json: Option<String>,
        coin: &mut Coin<MYS>,
        ctx: &mut TxContext
    ) {
        submit_proposal(
            registry,
            PROPOSAL_TYPE_REPUTATION,
            title,
            description,
            option::some(disputed_profile_id),
            reference_id,
            metadata_json,
            coin,
            ctx
        );
    }

    /// Submit a special proposal for community note
    public entry fun submit_community_note(
        registry: &mut GovernanceDAO,
        title: String,
        description: String,
        disputed_content_id: ID,
        reference_id: Option<ID>,
        metadata_json: Option<String>,
        coin: &mut Coin<MYS>,
        ctx: &mut TxContext
    ) {
        submit_proposal(
            registry,
            PROPOSAL_TYPE_COMMUNITY_NOTES,
            title,
            description,
            option::some(disputed_content_id),
            reference_id,
            metadata_json,
            coin,
            ctx
        );
    }

    /// Internal function for submitting proposals
    fun submit_proposal_internal(
        registry: &mut GovernanceDAO,
        title: String,
        description: String,
        proposal_type: u8,
        reference_id: Option<ID>,
        metadata_json: Option<String>,
        coin: &mut Coin<MYS>,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Check stake amount
        assert!(coin::value(coin) >= registry.proposal_submission_cost, EInvalidAmount);
        
        // Create proposal
        let proposal_id = object::new(ctx);
        let mut proposal = Proposal {
            id: proposal_id,
            title: title,
            description: description,
            proposal_type: proposal_type,
            reference_id: reference_id,
            metadata_json: metadata_json,
            submitter: caller,
            submission_time: current_time,
            delegate_approval_count: 0,
            delegate_rejection_count: 0,
            community_votes_for: 0,
            community_votes_against: 0,
            status: STATUS_DELEGATE_REVIEW,
            voting_start_time: 0,
            voting_end_time: 0,
            reward_pool: balance::zero(),
        };
        
        // Split coin and add to proposal's reward pool
        let proposal_coin = coin::split(coin, registry.proposal_submission_cost, ctx);
        balance::join(&mut proposal.reward_pool, coin::into_balance(proposal_coin));
        
        // Initialize dynamic fields for vote tracking
        let delegate_votes = table::new<address, bool>(ctx);
        dynamic_field::add(&mut proposal.id, DELEGATE_VOTES_FIELD, delegate_votes);
        
        let voted_community = vec_set::empty<address>();
        dynamic_field::add(&mut proposal.id, VOTED_COMMUNITY_FIELD, voted_community);
        
        // Add "voted for" and "voted against" tracking for easier reward distribution
        let voted_for = vec_set::empty<address>();
        dynamic_field::add(&mut proposal.id, VOTED_FOR_FIELD, voted_for);
        
        let voted_against = vec_set::empty<address>();
        dynamic_field::add(&mut proposal.id, VOTED_AGAINST_FIELD, voted_against);
        
        // Add proposal to registry
        let proposal_id_copy = object::id(&proposal);
        table::add(&mut registry.proposals, proposal_id_copy, proposal);
        
        // Add to proposals by status
        let proposals_of_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_DELEGATE_REVIEW);
        vector::push_back(proposals_of_status, proposal_id_copy);
        
        // Increment proposal count for delegate if applicable
        if (table::contains(&registry.delegates, caller)) {
            let delegate = table::borrow_mut(&mut registry.delegates, caller);
            delegate.proposals_submitted = delegate.proposals_submitted + 1;
        };
        
        // Emit event
        event::emit(ProposalSubmittedEvent {
            proposal_id: proposal_id_copy,
            title: title,
            description: description,
            proposal_type: proposal_type,
            reference_id: reference_id,
            metadata_json: metadata_json,
            submitter: caller,
            reward_amount: registry.proposal_submission_cost,
            submission_time: current_time,
        });
    }

    /// Allow a proposal owner to rescind their proposal if it's still in the delegate review stage
    public entry fun rescind_proposal(
        registry: &mut GovernanceDAO,
        proposal_id: ID,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Verify proposal exists and is in delegate review phase
        assert!(table::contains(&registry.proposals, proposal_id), EProposalNotFound);
        let proposal = table::borrow(&registry.proposals, proposal_id);
        
        // Verify caller is the proposal submitter
        assert!(proposal.submitter == caller, EUnauthorized);
        
        // Verify proposal is still in delegate review stage
        assert!(proposal.status == STATUS_DELEGATE_REVIEW, EInvalidProposalStatus);
        
        // Remove proposal from the registry to modify it
        let mut proposal = table::remove(&mut registry.proposals, proposal_id);
        
        // Update proposals by status - remove from delegate review
        let from_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_DELEGATE_REVIEW);
        let mut index = 0;
        let len = vector::length(from_status);
        while (index < len) {
            if (*vector::borrow(from_status, index) == proposal_id) {
                vector::remove(from_status, index);
                break
            };
            index = index + 1;
        };
        
        // Return staked tokens to submitter
        let refund_amount = balance::value(&proposal.reward_pool);
        if (refund_amount > 0) {
            let refund_coin = coin::from_balance(balance::withdraw_all(&mut proposal.reward_pool), ctx);
            transfer::public_transfer(refund_coin, caller);
        } else {
            // Empty the balance even if zero, for consistency
            balance::destroy_zero(balance::withdraw_all(&mut proposal.reward_pool));
        };
        
        // Emit event for the rescinded proposal
        event::emit(ProposalRescindedEvent {
            proposal_id,
            submitter: caller,
            rescind_time: current_time,
            refund_amount,
        });
        
        // Update proposal status to owner rescinded
        proposal.status = STATUS_OWNER_RESCIND;
        
        // Add to rejected proposals list (we still use the rejected table for tracking)
        let to_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_OWNER_RESCIND);
        vector::push_back(to_status, proposal_id);
        
        // Add the modified proposal back to the registry
        table::add(&mut registry.proposals, proposal_id, proposal);
    }

    /// Delegate votes on a proposal if it should move to community voting
    public entry fun delegate_vote_on_proposal(
        registry: &mut GovernanceDAO,
        proposal_id: ID,
        approve: bool,
        mut reason: Option<String>,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Verify caller is a delegate
        assert!(table::contains(&registry.delegates, caller), ENotDelegate);
        
        // Verify proposal exists and is in delegate review phase
        assert!(table::contains(&registry.proposals, proposal_id), EProposalNotFound);
        let proposal = table::borrow_mut(&mut registry.proposals, proposal_id);
        assert!(proposal.status == STATUS_DELEGATE_REVIEW, EInvalidProposalStatus);
        
        // Check if delegate has already voted
        let delegate_votes: &mut Table<address, bool> = dynamic_field::borrow_mut(&mut proposal.id, DELEGATE_VOTES_FIELD);
        assert!(!table::contains(delegate_votes, caller), EAlreadyVoted);
        
        // Record vote
        table::add(delegate_votes, caller, approve);
        
        // Store delegate's reason if provided
        if (option::is_some(&reason)) {
            // Initialize reason table if it doesn't exist
            if (!dynamic_field::exists_(&proposal.id, DELEGATE_REASONS_FIELD)) {
                let reason_table = table::new<address, String>(ctx);
                dynamic_field::add(&mut proposal.id, DELEGATE_REASONS_FIELD, reason_table);
            };
            
            // Add delegate's reason to the table
            let reason_table: &mut Table<address, String> = dynamic_field::borrow_mut(&mut proposal.id, DELEGATE_REASONS_FIELD);
            table::add(reason_table, caller, option::extract(&mut reason));
        };
        
        // Add delegate to the list of voted delegates (for later tracking)
        if (!dynamic_field::exists_(&proposal.id, VOTED_DELEGATES_LIST_FIELD)) {
            let delegates_list = vector::empty<address>();
            dynamic_field::add(&mut proposal.id, VOTED_DELEGATES_LIST_FIELD, delegates_list);
        };
        let delegates_list: &mut vector<address> = dynamic_field::borrow_mut(&mut proposal.id, VOTED_DELEGATES_LIST_FIELD);
        vector::push_back(delegates_list, caller);
        
        // Update vote counts - one vote per delegate (no multiplier)
        if (approve) {
            proposal.delegate_approval_count = proposal.delegate_approval_count + 1;
        } else {
            proposal.delegate_rejection_count = proposal.delegate_rejection_count + 1;
        };
        
        // Update delegate stats
        let delegate = table::borrow_mut(&mut registry.delegates, caller);
        delegate.proposals_reviewed = delegate.proposals_reviewed + 1;
        
        // Capture vote counts for decision making after event emission
        let delegate_approval_count = proposal.delegate_approval_count;
        let delegate_rejection_count = proposal.delegate_rejection_count;
        let total_delegates = table::length(&registry.delegates);
        
        // Emit event - restore the original reason for event emission
        let reason_for_event = reason;
        
        event::emit(DelegateVoteEvent {
            proposal_id,
            delegate_address: caller,
            approve,
            vote_time: current_time,
            reason: reason_for_event,
        });
       
        // If more than half of delegates approve, move to community voting
        if (delegate_approval_count > total_delegates / 2) {
            move_to_community_voting_by_id(registry, proposal_id, ctx);
        } 
        // If more than half of delegates reject, reject the proposal
        else if (delegate_rejection_count > total_delegates / 2) {
            reject_proposal_by_id(registry, proposal_id, current_time, ctx);
        };
    }

    /// Move a proposal to community voting phase
    fun move_to_community_voting_by_id(
        registry: &mut GovernanceDAO,
        proposal_id: ID,
        ctx: &TxContext
    ) {
        // Get proposal from registry
        let mut proposal = table::remove(&mut registry.proposals, proposal_id);
        
        // Update status
        proposal.status = STATUS_COMMUNITY_VOTING;
        
        // Get current epoch for voting period calculation
        let current_epoch = tx_context::epoch(ctx);
        
        // Set voting period based on registry voting period (using epochs)
        // This ensures voting ends on epoch boundaries, not millisecond timestamps
        proposal.voting_start_time = current_epoch;
        proposal.voting_end_time = current_epoch + registry.voting_period_epochs;
        
        // Update proposals by status
        let from_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_DELEGATE_REVIEW);
        let mut index = 0;
        let len = vector::length(from_status);
        while (index < len) {
            if (*vector::borrow(from_status, index) == proposal_id) {
                vector::remove(from_status, index);
                break
            };
            index = index + 1;
        };
        
        let to_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_COMMUNITY_VOTING);
        vector::push_back(to_status, proposal_id);
        
        // Put proposal back in registry
        table::add(&mut registry.proposals, proposal_id, proposal);
        
        // Emit event - use the precise timestamp for the event
        event::emit(ProposalApprovedForVotingEvent {
            proposal_id,
            voting_start_time: current_epoch,
            voting_end_time: current_epoch + registry.voting_period_epochs,
        });
    }

    /// Reject a proposal by ID (avoids reference issues)
    fun reject_proposal_by_id(
        registry: &mut GovernanceDAO,
        proposal_id: ID,
        current_time: u64,
        ctx: &mut TxContext
    ) {
        // Get proposal from registry
        let mut proposal = table::remove(&mut registry.proposals, proposal_id);
        
        // Update status
        proposal.status = STATUS_REJECTED;
        
        // Update proposals by status
        let from_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_DELEGATE_REVIEW);
        let mut index = 0;
        let len = vector::length(from_status);
        while (index < len) {
            if (*vector::borrow(from_status, index) == proposal_id) {
                vector::remove(from_status, index);
                break
            };
            index = index + 1;
        };
        
        let to_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_REJECTED);
        vector::push_back(to_status, proposal_id);
        
        // Return funds to submitter
        let submitter = proposal.submitter;
        let refund_amount = balance::value(&proposal.reward_pool);
        
        if (refund_amount > 0) {
            let refund_coin = coin::from_balance(balance::withdraw_all(&mut proposal.reward_pool), ctx);
            transfer::public_transfer(refund_coin, submitter);
        } else {
            // Empty the balance even if zero, for consistency
            balance::destroy_zero(balance::withdraw_all(&mut proposal.reward_pool));
        };
        
        // Put modified proposal back in registry
        table::add(&mut registry.proposals, proposal_id, proposal);
        
        // Emit event
        event::emit(ProposalRejectedEvent {
            proposal_id,
            rejection_time: current_time,
        });
    }

    /// Community vote on a proposal with quadratic voting
    /// Users can cast multiple votes by paying a quadratically increasing cost
    public entry fun community_vote_on_proposal(
        registry: &mut GovernanceDAO,
        proposal_id: ID,
        vote_count: u64,
        approve: bool,
        coin: &mut Coin<MYS>,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        // Also get the current epoch for timing checks
        let current_epoch = tx_context::epoch(ctx);
        
        // Calculate vote cost before borrowing from registry
        let quadratic_base_cost = registry.quadratic_base_cost;
        let vote_cost = if (vote_count <= 1) {
            0
        } else {
            // Quadratic cost formula: base_cost * (vote_count^2 - 1)
            quadratic_base_cost * ((vote_count * vote_count) - 1)
        };
        
        // Verify proposal exists and is in community voting phase
        assert!(table::contains(&registry.proposals, proposal_id), EProposalNotFound);
        let proposal = table::borrow_mut(&mut registry.proposals, proposal_id);
        assert!(proposal.status == STATUS_COMMUNITY_VOTING, ENotVotingPhase);
        
        // Verify voting period hasn't ended (check using epochs, not milliseconds)
        assert!(current_epoch <= proposal.voting_end_time, EVotingPeriodEnded);
        
        // Verify vote count is valid (at least 1, no more than max)
        assert!(vote_count > 0, EInvalidVoteCount);
        assert!(vote_count <= registry.max_votes_per_user, EExceedsMaxVotes);
        
        // Check if user has already voted
        let voted_community: &mut VecSet<address> = dynamic_field::borrow_mut(&mut proposal.id, VOTED_COMMUNITY_FIELD);
        assert!(!vec_set::contains(voted_community, &caller), EAlreadyVoted);
        
        // Check if user has enough funds for votes
        if (vote_cost > 0) {
            assert!(coin::value(coin) >= vote_cost, EInvalidAmount);
            
            // Split coin and add to proposal's reward pool for the additional votes
            let vote_coin = coin::split(coin, vote_cost, ctx);
            balance::join(&mut proposal.reward_pool, coin::into_balance(vote_coin));
        };
        
        // Record vote
        vec_set::insert(voted_community, caller);
        
        // Update vote tally
        if (approve) {
            proposal.community_votes_for = proposal.community_votes_for + vote_count;
            // Add to voted_for set for reward distribution
            let voted_for: &mut VecSet<address> = dynamic_field::borrow_mut(&mut proposal.id, VOTED_FOR_FIELD);
            vec_set::insert(voted_for, caller);
        } else {
            proposal.community_votes_against = proposal.community_votes_against + vote_count;
            // Add to voted_against set for reward distribution
            let voted_against: &mut VecSet<address> = dynamic_field::borrow_mut(&mut proposal.id, VOTED_AGAINST_FIELD);
            vec_set::insert(voted_against, caller);
        };
        
        // Emit event (use millisecond timestamp for the event record)
        event::emit(CommunityVoteEvent {
            proposal_id,
            voter: caller,
            vote_weight: vote_count,
            approve,
            vote_time: current_time,
            vote_cost,
        });
    }

    /// Finalize a proposal after the voting period ends
    public entry fun finalize_proposal(
        registry: &mut GovernanceDAO,
        proposal_id: ID,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Verify proposal exists and is in community voting phase
        assert!(table::contains(&registry.proposals, proposal_id), EProposalNotFound);
        let proposal = table::borrow_mut(&mut registry.proposals, proposal_id);
        assert!(proposal.status == STATUS_COMMUNITY_VOTING, EInvalidProposalStatus);
        
        // Verify voting period has ended (using epoch-based timing)
        assert!(current_epoch > proposal.voting_end_time, EVotingPeriodNotEnded);
        
        // Get total votes
        let total_votes = proposal.community_votes_for + proposal.community_votes_against;
        
        // Update proposals by status
        let from_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_COMMUNITY_VOTING);
        let mut index = 0;
        let len = vector::length(from_status);
        while (index < len) {
            if (*vector::borrow(from_status, index) == proposal_id) {
                vector::remove(from_status, index);
                break
            };
            index = index + 1;
        };
        
        // Check if quorum is reached (using registry's quorum_votes)
        let quorum_met = total_votes >= registry.quorum_votes;
        let majority_approve = proposal.community_votes_for > proposal.community_votes_against;
        
        if (quorum_met) {
            // Update delegate winning/losing votes if they exist in the proposal
            if (dynamic_field::exists_(&proposal.id, VOTED_DELEGATES_LIST_FIELD)) {
                let delegates_list: &vector<address> = dynamic_field::borrow(&proposal.id, VOTED_DELEGATES_LIST_FIELD);
                let delegate_votes: &Table<address, bool> = dynamic_field::borrow(&proposal.id, DELEGATE_VOTES_FIELD);
                
                let mut i = 0;
                let delegates_count = vector::length(delegates_list);
                
                while (i < delegates_count) {
                    let delegate_addr = *vector::borrow(delegates_list, i);
                    
                    // Only update if the delegate still exists in the registry
                    if (table::contains(&registry.delegates, delegate_addr)) {
                        let delegate = table::borrow_mut(&mut registry.delegates, delegate_addr);
                        let delegate_approved = *table::borrow(delegate_votes, delegate_addr);
                        
                        // Update winning/losing counts based on matching the majority
                        if ((delegate_approved && majority_approve) || (!delegate_approved && !majority_approve)) {
                            delegate.sided_winning_proposals = delegate.sided_winning_proposals + 1;
                        } else {
                            delegate.sided_losing_proposals = delegate.sided_losing_proposals + 1;
                        };
                    };
                    
                    i = i + 1;
                };
            };
            
            // Determine outcome
            if (majority_approve) {
                // Proposal approved
                proposal.status = STATUS_APPROVED;
                
                let to_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_APPROVED);
                vector::push_back(to_status, proposal_id);
                
                // Emit approval event
                event::emit(ProposalApprovedEvent {
                    proposal_id,
                    approval_time: current_time,
                    votes_for: proposal.community_votes_for,
                    votes_against: proposal.community_votes_against,
                });
                
                // Distribute rewards to winning voters
                distribute_rewards(proposal, true, ctx);
            } else {
                // Proposal rejected
                proposal.status = STATUS_REJECTED;
                
                let to_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_REJECTED);
                vector::push_back(to_status, proposal_id);
                
                // Emit rejection event
                event::emit(ProposalRejectedByCommunityEvent {
                    proposal_id,
                    rejection_time: current_time,
                    votes_for: proposal.community_votes_for,
                    votes_against: proposal.community_votes_against,
                });
                
                // Distribute rewards to losing voters
                distribute_rewards(proposal, false, ctx);
            }
        } else {
            // Quorum not reached, proposal rejected
            proposal.status = STATUS_REJECTED;
            
            let to_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_REJECTED);
            vector::push_back(to_status, proposal_id);
            
            // Emit rejection event
            event::emit(ProposalRejectedByCommunityEvent {
                proposal_id,
                rejection_time: current_time,
                votes_for: proposal.community_votes_for,
                votes_against: proposal.community_votes_against,
            });
            
            // Return funds to proposer since quorum wasn't reached
            let submitter = proposal.submitter;
            let refund_amount = balance::value(&proposal.reward_pool);
            
            if (refund_amount > 0) {
                let refund_coin = coin::from_balance(balance::withdraw_all(&mut proposal.reward_pool), ctx);
                transfer::public_transfer(refund_coin, submitter);
            } else {
                // Empty the balance even if zero, for consistency
                balance::destroy_zero(balance::withdraw_all(&mut proposal.reward_pool));
            };
        }
    }

    /// Distribute rewards to winning voters
    /// Rewards are distributed equally among all voters who voted for the winning side
    fun distribute_rewards(
        proposal: &mut Proposal,
        approve_won: bool,
        ctx: &mut TxContext
    ) {
        // Get the total reward amount
        let total_reward = balance::value(&proposal.reward_pool);
        
        if (total_reward == 0) {
            return // No rewards to distribute
        };
        
        // Get the field name based on which side won
        let field_name = if (approve_won) VOTED_FOR_FIELD else VOTED_AGAINST_FIELD;
        let winner_voters: &VecSet<address> = dynamic_field::borrow(&proposal.id, field_name);
        let voters_vec = vec_set::into_keys(*winner_voters);
        let voter_count = vector::length(&voters_vec);
        
        if (voter_count == 0) {
            // No winners, return funds to proposer
            let reward_coin = coin::from_balance(balance::withdraw_all(&mut proposal.reward_pool), ctx);
            transfer::public_transfer(reward_coin, proposal.submitter);
            vector::destroy_empty(voters_vec);
            return
        };
        
        // Calculate per voter reward
        let per_voter_reward = total_reward / voter_count;
        
        // There could be dust left due to division
        let total_distributed = per_voter_reward * voter_count;
        let dust = if (total_distributed < total_reward) {
            total_reward - total_distributed
        } else {
            0
        };
        
        // Distribute the bulk of the rewards
        let mut idx = 0;
        while (idx < voter_count) {
            let voter = *vector::borrow(&voters_vec, idx);
            let reward_amount = if (idx == voter_count - 1) { per_voter_reward + dust } else { per_voter_reward };
            if (reward_amount > 0) {
                let balance = balance::split(&mut proposal.reward_pool, reward_amount);
                let reward_coin = coin::from_balance(balance, ctx);
                transfer::public_transfer(reward_coin, voter);
            };
            idx = idx + 1;
        };
        
        // Emit event for reward distribution
        assert!(balance::value(&proposal.reward_pool) == 0, EInvalidAmount);

        event::emit(RewardsDistributedEvent {
            proposal_id: object::id(proposal),
            total_reward,
            recipient_count: voter_count,
            distribution_time: tx_context::epoch_timestamp_ms(ctx),
        });
        vector::destroy_empty(voters_vec);
    }

    /// Mark a proposal as implemented
    public entry fun mark_proposal_implemented(
        registry: &mut GovernanceDAO,
        proposal_id: ID,
        description: Option<String>,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        
        // Verify proposal exists and is approved
        assert!(table::contains(&registry.proposals, proposal_id), EProposalNotFound);
        let proposal = table::borrow_mut(&mut registry.proposals, proposal_id);
        assert!(proposal.status == STATUS_APPROVED, EInvalidProposalStatus);
        
        // Only the submitter or a delegate can mark as implemented
        assert!(
            proposal.submitter == caller || table::contains(&registry.delegates, caller),
            EUnauthorized
        );
        
        // Update status
        proposal.status = STATUS_IMPLEMENTED;
        
        // Update proposals by status
        let from_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_APPROVED);
        let mut index = 0;
        let len = vector::length(from_status);
        while (index < len) {
            if (*vector::borrow(from_status, index) == proposal_id) {
                vector::remove(from_status, index);
                break
            };
            index = index + 1;
        };
        
        let to_status = table::borrow_mut(&mut registry.proposals_by_status, STATUS_IMPLEMENTED);
        vector::push_back(to_status, proposal_id);
        
        // Emit event
        event::emit(ProposalImplementedEvent {
            proposal_id,
            implementation_time: current_time,
            description,
        });
    }

    /// Get all proposals of a specific type
    public fun get_proposals_by_type(
        registry: &GovernanceDAO,
        proposal_type: u8
    ): vector<ID> {
        assert!(proposal_type <= PROPOSAL_TYPE_PLATFORM, EInvalidParameter);
        let mut result = vector::empty<ID>();
        let statuses = vector[ STATUS_SUBMITTED, STATUS_DELEGATE_REVIEW, STATUS_COMMUNITY_VOTING, STATUS_APPROVED, STATUS_REJECTED, STATUS_IMPLEMENTED ];
        let mut s = 0;
        while (s < vector::length(&statuses)) {
            let status = *vector::borrow(&statuses, s);
            let proposals_of_status: &vector<ID> = table::borrow(&registry.proposals_by_status, status);
            let mut p = 0;
            let num_proposals = vector::length(proposals_of_status);
            
            while (p < num_proposals) {
                let proposal_id = *vector::borrow(proposals_of_status, p);
                let proposal: &Proposal = table::borrow(&registry.proposals, proposal_id);
                if (proposal.proposal_type == proposal_type) {
                    vector::push_back(&mut result, proposal_id);
                };
                
                p = p + 1;
            };
            
            s = s + 1;
        };
        vector::destroy_empty(statuses);
        result
    }

    /// Get all proposals with a specific status
    public fun get_proposals_by_status(
        registry: &GovernanceDAO,
        status: u8
    ): vector<ID> {
        assert!(status <= STATUS_IMPLEMENTED, EInvalidParameter);
        *table::borrow(&registry.proposals_by_status, status)
    }

    /// Get number of delegates
    public fun get_delegate_count(registry: &GovernanceDAO): u64 {
        table::length(&registry.delegates)
    }

    /// Get delegate information
    public fun get_delegate_info(
        registry: &GovernanceDAO,
        addr: address
    ): (ID, u64, u64, u64, u64, u64, u64, u64, u64) {
        assert!(table::contains(&registry.delegates, addr), ENotDelegate);
        
        let delegate = table::borrow(&registry.delegates, addr);
        (
            delegate.profile_id,
            delegate.upvotes,
            delegate.downvotes,
            delegate.proposals_reviewed,
            delegate.proposals_submitted,
            delegate.sided_winning_proposals,
            delegate.sided_losing_proposals,
            delegate.term_start,
            delegate.term_end
        )
    }

    /// Get proposal information
    public fun get_proposal_info(
        registry: &GovernanceDAO,
        id: ID
    ): (String, String, u8, Option<ID>, Option<String>, address, u64, u8, u64, u64) {
        assert!(table::contains(&registry.proposals, id), EProposalNotFound);
        
        let proposal = table::borrow(&registry.proposals, id);
        (
            proposal.title,
            proposal.description,
            proposal.proposal_type,
            proposal.reference_id,
            proposal.metadata_json,
            proposal.submitter,
            proposal.submission_time,
            proposal.status,
            proposal.community_votes_for,
            proposal.community_votes_against
        )
    }

    /// Get the current treasury balance
    public fun treasury_balance(registry: &GovernanceDAO): u64 {
        balance::value(&registry.treasury)
    }

    /// Calculate cost for additional votes beyond the first free vote
    public fun calculate_vote_cost(
        vote_count: u64,
        registry: &GovernanceDAO
    ): u64 {
        if (vote_count <= 1) {
            return 0
        };
        
        // Quadratic cost formula: base_cost * (vote_count^2 - 1)
        registry.quadratic_base_cost * ((vote_count * vote_count) - 1)
    }

    /// Check if an address is a delegate
    public fun is_delegate( registry: &GovernanceDAO, addr: address ): bool {
        table::contains(&registry.delegates, addr)
    }

    /// Check if delegate term has expired
    public fun is_delegate_term_expired(
        registry: &GovernanceDAO,
        addr: address,
        current_epoch: u64
    ): bool {
        if (!table::contains(&registry.delegates, addr)) {
            return false
        };
        
        let delegate = table::borrow(&registry.delegates, addr);
        delegate.term_end <= current_epoch
    }

    /// Get governance parameters
    public fun get_governance_parameters(
        registry: &GovernanceDAO
    ): (u64, u64, u64, u64, u64, u64, u64, u64) {
        (
            registry.delegate_count,
            registry.delegate_term_epochs,
            registry.proposal_submission_cost,
            registry.min_on_chain_age_days,
            registry.max_votes_per_user,
            registry.quadratic_base_cost,
            registry.voting_period_epochs,
            registry.quorum_votes
        )
    }

    /// If more than half of delegates reject, reject the proposal manually
    public entry fun reject_proposal_manually(
        registry: &mut GovernanceDAO,
        proposal_id: ID,
        ctx: &mut TxContext
    ) {
        // Verify caller is a delegate
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.delegates, caller), ENotDelegate);
        
        // Verify proposal exists and is in delegate review phase
        assert!(table::contains(&registry.proposals, proposal_id), EProposalNotFound);
        let proposal = table::borrow(&registry.proposals, proposal_id);
        assert!(proposal.status == STATUS_DELEGATE_REVIEW, EInvalidProposalStatus);
        
        // Reject the proposal
        let current_time = tx_context::epoch_timestamp_ms(ctx);
        reject_proposal_by_id(registry, proposal_id, current_time, ctx);
    }

    /// Create a platform-specific governance registry when a platform is approved
    /// This function can only be called by the platform toggle_platform_approval function
    /// and only the package publisher can call it
    public fun create_platform_governance(
        delegate_count: u64,
        delegate_term_epochs: u64,
        proposal_submission_cost: u64,
        min_on_chain_age_days: u64,
        max_votes_per_user: u64,
        quadratic_base_cost: u64,
        voting_period_epochs: u64,
        quorum_votes: u64,
        ctx: &mut TxContext
    ): ID {
        // Create Platform Governance Registry with parameters
        let mut platform_registry = GovernanceDAO {
            id: object::new(ctx),
            registry_type: PROPOSAL_TYPE_PLATFORM,
            // Configuration parameters specific to platform governance
            delegate_count, 
            delegate_term_epochs,
            proposal_submission_cost,
            min_on_chain_age_days,
            max_votes_per_user,
            quadratic_base_cost,
            voting_period_epochs,
            quorum_votes,
            // Tables
            delegates: table::new<address, Delegate>(ctx),
            proposals: table::new<ID, Proposal>(ctx),
            proposals_by_status: table::new<u8, vector<ID>>(ctx),
            treasury: balance::zero(),
            nominated_delegates: table::new<address, NominatedDelegate>(ctx),
            delegate_addresses: vec_set::empty<address>(),
            nominee_addresses: vec_set::empty<address>(),
            voters: table::new<address, Table<address, bool>>(ctx),
            version: upgrade::current_version(),
        };
        
        // Initialize registry tables
        initialize_registry_tables(&mut platform_registry, ctx);
        
        // Get the ID before sharing
        let registry_id = object::id(&platform_registry);
        
        // Share the registry object
        transfer::share_object(platform_registry);
        
        // Return the registry ID
        registry_id
    }

    /// Get version of GovernanceDAO
    public fun version(registry: &GovernanceDAO): u64 {
        registry.version
    }

    /// Set version of GovernanceDAO
    public fun set_version(registry: &mut GovernanceDAO, new_version: u64) {
        registry.version = new_version;
    }

    /// Public entry function that migrates registry to the latest version
    public entry fun migrate_registry(registry: &mut GovernanceDAO, _ctx: &mut TxContext) {
        let current_version = registry.version;
        let latest_version = upgrade::current_version();

        assert!(current_version < latest_version, EWrongVersion);

        // Version-specific migrations would go here when needed
        
        registry.version = latest_version;
    }
}
