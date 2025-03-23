module social_contracts::proof_of_creativity {
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    
    use mys::object::{Self, UID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer;
    use mys::table::{Self, Table};
    use mys::url::{Self, Url};
    use social_contracts::profile::{Self, Profile};
    use mys::clock::{Self, Clock};
    use social_contracts::my_ip::{Self, MyIP};
    
    /// Error codes
    const EUnauthorized: u64 = 0;
    const EInvalidVerificationState: u64 = 1;
    const EInvalidProofType: u64 = 2;
    const EProviderNotAuthorized: u64 = 3;
    const EProofAlreadyVerified: u64 = 4;
    const EProofRejected: u64 = 5;
    
    /// Verification states for proofs
    const VERIFICATION_PENDING: u8 = 0;
    const VERIFICATION_APPROVED: u8 = 1;
    const VERIFICATION_REJECTED: u8 = 2;
    
    /// Proof types
    const PROOF_TYPE_TIMESTAMPED: u8 = 0;      // Timestamp-based proof
    const PROOF_TYPE_WITNESSED: u8 = 1;        // Witnessed/notarized proof
    const PROOF_TYPE_CRYPTOGRAPHIC: u8 = 2;    // Cryptographic proof with signatures
    const PROOF_TYPE_AI_ANALYSIS: u8 = 3;      // AI-based analysis proof
    const PROOF_TYPE_PLAGIARISM_CHECK: u8 = 4; // Plagiarism detection results
    const PROOF_TYPE_EXTERNAL: u8 = 5;         // External verification system
    
    /// Proof of Creativity object representing evidence of original creation
    public struct ProofOfCreativity has key, store {
        id: UID,
        /// Creator's profile ID
        creator: address,
        /// Title of the proof
        title: String,
        /// Description of the proof and creative process
        description: String,
        /// Type of proof (timestamp, witnessed, etc.)
        proof_type: u8,
        /// URLs to evidence files (can be multiple)
        evidence_urls: vector<Url>,
        /// Hash of all evidence files concatenated
        evidence_hash: vector<u8>,
        /// References to earlier work or inspiration
        references: vector<String>,
        /// External validators or witnesses
        validators: vector<address>,
        /// Verification state
        verification_state: u8,
        /// Verification provider (if applicable)
        verification_provider: Option<address>,
        /// Verification timestamp
        verification_time: u64,
        /// Verification notes/details
        verification_notes: String,
        /// Creation timestamp
        created_at: u64,
    }
    
    /// Verification request for a Proof of Creativity
    public struct VerificationRequest has key {
        id: UID,
        /// Proof of Creativity ID
        poc_id: address,
        /// Provider who will verify
        provider: address,
        /// Creator requesting verification
        creator: address,
        /// Request timestamp
        requested_at: u64,
        /// Status of the request
        status: u8,
    }
    
    /// Registry for verification providers
    public struct VerificationProviderRegistry has key {
        id: UID,
        /// Table of authorized verification providers
        providers: Table<address, bool>,
        /// Admin address
        admin: address,
    }
    
    /// Events
    
    /// Event emitted when a new Proof of Creativity is created
    public struct ProofCreatedEvent has copy, drop {
        poc_id: address,
        creator: address,
        title: String,
        proof_type: u8,
        created_at: u64,
    }
    
    /// Event emitted when a Proof of Creativity is verified
    public struct ProofVerifiedEvent has copy, drop {
        poc_id: address,
        creator: address,
        provider: address,
        verification_state: u8,
        verification_time: u64,
    }
    
    /// Event emitted when a verification request is created
    public struct VerificationRequestedEvent has copy, drop {
        request_id: address,
        poc_id: address,
        creator: address,
        provider: address,
        requested_at: u64,
    }
    
    /// Event emitted when a provider is registered
    public struct ProviderRegisteredEvent has copy, drop {
        provider: address,
        registered_by: address,
    }
    
    /// Initialize the verification provider registry
    fun init_module(ctx: &mut TxContext) {
        let registry = VerificationProviderRegistry {
            id: object::new(ctx),
            providers: table::new(ctx),
            admin: tx_context::sender(ctx),
        };
        
        // Share the registry as a shared object
        transfer::share_object(registry);
    }
    
    /// Create a new Proof of Creativity
    public fun create_proof(
        creator_profile: &Profile,
        title: String,
        description: String,
        proof_type: u8,
        evidence_urls: vector<vector<u8>>,
        evidence_hash: vector<u8>,
        references: vector<String>,
        validators: vector<address>,
        ctx: &mut TxContext
    ): ProofOfCreativity {
        // Verify proof type is valid
        assert!(
            proof_type == PROOF_TYPE_TIMESTAMPED || 
            proof_type == PROOF_TYPE_WITNESSED || 
            proof_type == PROOF_TYPE_CRYPTOGRAPHIC || 
            proof_type == PROOF_TYPE_AI_ANALYSIS ||
            proof_type == PROOF_TYPE_PLAGIARISM_CHECK ||
            proof_type == PROOF_TYPE_EXTERNAL,
            EInvalidProofType
        );
        
        let creator_id = object::uid_to_address(profile::id(creator_profile));
        
        // Convert evidence URL bytes to Url objects
        let mut urls = vector::empty<Url>();
        let mut i = 0;
        let len = vector::length(&evidence_urls);
        
        while (i < len) {
            let url_bytes = *vector::borrow(&evidence_urls, i);
            vector::push_back(&mut urls, url::new_unsafe_from_bytes(url_bytes));
            i = i + 1;
        };
        
        let poc = ProofOfCreativity {
            id: object::new(ctx),
            creator: creator_id,
            title,
            description,
            proof_type,
            evidence_urls: urls,
            evidence_hash,
            references,
            validators,
            verification_state: VERIFICATION_PENDING,
            verification_provider: option::none(),
            verification_time: 0,
            verification_notes: string::utf8(b""),
            created_at: tx_context::epoch(ctx),
        };
        
        let poc_id = object::uid_to_address(&poc.id);
        
        // Emit proof created event
        event::emit(ProofCreatedEvent {
            poc_id,
            creator: creator_id,
            title: poc.title,
            proof_type: poc.proof_type,
            created_at: poc.created_at,
        });
        
        poc
    }
    
    /// Create and register a new Proof of Creativity and transfer to creator
    public entry fun register_proof(
        creator_profile: &Profile,
        title: String,
        description: String,
        proof_type: u8,
        evidence_urls: vector<vector<u8>>,
        evidence_hash: vector<u8>,
        references: vector<String>,
        validators: vector<address>,
        ctx: &mut TxContext
    ) {
        let poc = create_proof(
            creator_profile,
            title,
            description,
            proof_type,
            evidence_urls,
            evidence_hash,
            references,
            validators,
            ctx
        );
        
        // Transfer proof to creator
        transfer::transfer(poc, tx_context::sender(ctx));
    }
    
    /// Register a verification provider (admin only)
    public entry fun register_provider(
        registry: &mut VerificationProviderRegistry,
        provider: address,
        ctx: &mut TxContext
    ) {
        // Verify admin
        assert!(registry.admin == tx_context::sender(ctx), EUnauthorized);
        
        // Add provider to registry
        table::add(&mut registry.providers, provider, true);
        
        // Emit provider registered event
        event::emit(ProviderRegisteredEvent {
            provider,
            registered_by: tx_context::sender(ctx),
        });
    }
    
    /// Create a verification request
    public entry fun request_verification(
        poc: &ProofOfCreativity,
        creator_profile: &Profile,
        provider: address,
        registry: &VerificationProviderRegistry,
        ctx: &mut TxContext
    ) {
        let creator_id = object::uid_to_address(profile::id(creator_profile));
        
        // Verify creator owns the proof
        assert!(poc.creator == creator_id, EUnauthorized);
        
        // Verify provider is authorized
        assert!(table::contains(&registry.providers, provider), EProviderNotAuthorized);
        
        // Verify proof is still pending verification
        assert!(poc.verification_state == VERIFICATION_PENDING, EProofAlreadyVerified);
        
        let request = VerificationRequest {
            id: object::new(ctx),
            poc_id: object::uid_to_address(&poc.id),
            provider,
            creator: creator_id,
            requested_at: tx_context::epoch(ctx),
            status: VERIFICATION_PENDING,
        };
        
        let request_id = object::uid_to_address(&request.id);
        
        // Emit verification requested event
        event::emit(VerificationRequestedEvent {
            request_id,
            poc_id: request.poc_id,
            creator: request.creator,
            provider: request.provider,
            requested_at: request.requested_at,
        });
        
        // Share the request object
        transfer::share_object(request);
    }
    
    /// Verify a Proof of Creativity (provider only)
    public entry fun verify_proof(
        poc: &mut ProofOfCreativity,
        request: &mut VerificationRequest,
        provider_profile: &Profile,
        verification_state: u8,
        verification_notes: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let provider_id = object::uid_to_address(profile::id(provider_profile));
        
        // Verify provider is the one assigned to this request
        assert!(request.provider == provider_id, EUnauthorized);
        assert!(request.poc_id == object::uid_to_address(&poc.id), EUnauthorized);
        
        // Verify the state is valid
        assert!(
            verification_state == VERIFICATION_APPROVED || 
            verification_state == VERIFICATION_REJECTED,
            EInvalidVerificationState
        );
        
        // Update proof verification state
        poc.verification_state = verification_state;
        poc.verification_provider = option::some(provider_id);
        poc.verification_time = clock::timestamp_ms(clock) / 1000; // Convert ms to seconds
        poc.verification_notes = verification_notes;
        
        // Update request status
        request.status = verification_state;
        
        // Emit proof verified event
        event::emit(ProofVerifiedEvent {
            poc_id: object::uid_to_address(&poc.id),
            creator: poc.creator,
            provider: provider_id,
            verification_state,
            verification_time: poc.verification_time,
        });
    }
    
    /// Link Proof of Creativity to an IP asset
    public entry fun link_proof_to_ip(
        poc: &ProofOfCreativity,
        ip: &mut MyIP,
        creator_profile: &Profile,
        ctx: &mut TxContext
    ) {
        let creator_id = object::uid_to_address(profile::id(creator_profile));
        
        // Verify creator owns both the proof and the IP
        assert!(poc.creator == creator_id, EUnauthorized);
        assert!(my_ip::creator(ip) == creator_id, EUnauthorized);
        
        // Verify proof is verified
        assert!(poc.verification_state == VERIFICATION_APPROVED, EProofRejected);
        
        // Link the proof to the IP
        my_ip::set_poc_id(ip, object::uid_to_address(&poc.id));
    }
    
    // === Getters ===
    
    /// Get proof creator
    public fun creator(poc: &ProofOfCreativity): address {
        poc.creator
    }
    
    /// Get proof title
    public fun title(poc: &ProofOfCreativity): String {
        poc.title
    }
    
    /// Get proof description
    public fun description(poc: &ProofOfCreativity): String {
        poc.description
    }
    
    /// Get proof type
    public fun proof_type(poc: &ProofOfCreativity): u8 {
        poc.proof_type
    }
    
    /// Get evidence URLs
    public fun evidence_urls(poc: &ProofOfCreativity): &vector<Url> {
        &poc.evidence_urls
    }
    
    /// Get evidence hash
    public fun evidence_hash(poc: &ProofOfCreativity): vector<u8> {
        poc.evidence_hash
    }
    
    /// Get references
    public fun references(poc: &ProofOfCreativity): &vector<String> {
        &poc.references
    }
    
    /// Get validators
    public fun validators(poc: &ProofOfCreativity): &vector<address> {
        &poc.validators
    }
    
    /// Get verification state
    public fun verification_state(poc: &ProofOfCreativity): u8 {
        poc.verification_state
    }
    
    /// Get verification provider
    public fun verification_provider(poc: &ProofOfCreativity): &Option<address> {
        &poc.verification_provider
    }
    
    /// Get verification time
    public fun verification_time(poc: &ProofOfCreativity): u64 {
        poc.verification_time
    }
    
    /// Get verification notes
    public fun verification_notes(poc: &ProofOfCreativity): String {
        poc.verification_notes
    }
    
    /// Get creation time
    public fun created_at(poc: &ProofOfCreativity): u64 {
        poc.created_at
    }
    
    /// Check if proof is verified
    public fun is_verified(poc: &ProofOfCreativity): bool {
        poc.verification_state == VERIFICATION_APPROVED
    }
    
    /// Check if proof is rejected
    public fun is_rejected(poc: &ProofOfCreativity): bool {
        poc.verification_state == VERIFICATION_REJECTED
    }
    
    /// Check if proof is pending verification
    public fun is_pending(poc: &ProofOfCreativity): bool {
        poc.verification_state == VERIFICATION_PENDING
    }
}