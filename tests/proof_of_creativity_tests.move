// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module mys::proof_of_creativity_tests {
    use std::string;
    use std::vector;
    use std::option;
    
    use mys::test_scenario;
    use mys::profile::{Self, Profile};
    use mys::proof_of_creativity::{Self, ProofOfCreativity, VerificationProviderRegistry, VerificationRequest};
    use mys::my_ip::{Self, MyIP};
    use mys::clock::{Self, Clock};
    use mys::object;
    
    const ADMIN: address = @0xAD;
    const CREATOR: address = @0x1;
    const PROVIDER: address = @0x2;
    
    // Constants from proof_of_creativity module
    const VERIFICATION_PENDING: u8 = 0;
    const VERIFICATION_APPROVED: u8 = 1;
    const VERIFICATION_REJECTED: u8 = 2;
    
    const PROOF_TYPE_TIMESTAMPED: u8 = 0;
    
    // Helper function to create a test profile
    fun create_test_profile(scenario: &mut test_scenario::Scenario, name: vector<u8>): Profile {
        let display_name = string::utf8(name);
        let bio = string::utf8(b"Test bio");
        let profile_picture = option::some(mys::url::new_unsafe_from_bytes(b"https://example.com/profile.jpg"));
        
        profile::create_profile(
            display_name,
            bio,
            profile_picture,
            test_scenario::ctx(scenario)
        )
    }
    
    // Helper function to set up a test clock
    fun create_test_clock(scenario: &mut test_scenario::Scenario): Clock {
        clock::create_for_testing(test_scenario::ctx(scenario))
    }
    
    #[test]
    fun test_create_proof() {
        let scenario = test_scenario::begin(CREATOR);
        
        // Create a profile for CREATOR
        let creator_profile = create_test_profile(&mut scenario, b"Creator");
        mys::transfer::transfer(creator_profile, CREATOR);
        
        // Create a proof of creativity
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            let title = string::utf8(b"My Creative Work");
            let description = string::utf8(b"This is a description of my creative work");
            let proof_type = PROOF_TYPE_TIMESTAMPED;
            let evidence_urls = vector[b"https://example.com/evidence.jpg"];
            let evidence_hash = b"0123456789abcdef";
            let references = vector[string::utf8(b"Inspiration 1")];
            let validators = vector[];
            
            let poc = proof_of_creativity::create_proof(
                &profile,
                title,
                description,
                proof_type,
                evidence_urls,
                evidence_hash,
                references,
                validators,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify proof properties
            assert!(proof_of_creativity::creator(&poc) == object::uid_to_address(profile::id(&profile)), 0);
            assert!(proof_of_creativity::title(&poc) == title, 0);
            assert!(proof_of_creativity::description(&poc) == description, 0);
            assert!(proof_of_creativity::proof_type(&poc) == proof_type, 0);
            assert!(proof_of_creativity::is_pending(&poc), 0);
            assert!(!proof_of_creativity::is_verified(&poc), 0);
            assert!(!proof_of_creativity::is_rejected(&poc), 0);
            
            // Transfer the proof to the creator
            mys::transfer::transfer(poc, CREATOR);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_register_provider() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Initialize the module to create the registry
        {
            // Call is_module_initialized to initialize the module
            // (this is normally done by the Move VM during module publishing)
            test_scenario::next_tx(&mut scenario, ADMIN);
            proof_of_creativity::init_module(test_scenario::ctx(&mut scenario));
        };
        
        // Register a provider
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<VerificationProviderRegistry>(&scenario);
            
            proof_of_creativity::register_provider(
                &mut registry,
                PROVIDER,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_request_verification() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Initialize the module to create the registry
        {
            proof_of_creativity::init_module(test_scenario::ctx(&mut scenario));
        };
        
        // Register a provider
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<VerificationProviderRegistry>(&scenario);
            
            proof_of_creativity::register_provider(
                &mut registry,
                PROVIDER,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // Create a profile for CREATOR
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let creator_profile = create_test_profile(&mut scenario, b"Creator");
            mys::transfer::transfer(creator_profile, CREATOR);
        };
        
        // Create a proof of creativity
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            let title = string::utf8(b"My Creative Work");
            let description = string::utf8(b"This is a description of my creative work");
            let proof_type = PROOF_TYPE_TIMESTAMPED;
            let evidence_urls = vector[b"https://example.com/evidence.jpg"];
            let evidence_hash = b"0123456789abcdef";
            let references = vector[string::utf8(b"Inspiration 1")];
            let validators = vector[];
            
            proof_of_creativity::register_proof(
                &profile,
                title,
                description,
                proof_type,
                evidence_urls,
                evidence_hash,
                references,
                validators,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Request verification
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let poc = test_scenario::take_from_sender<ProofOfCreativity>(&scenario);
            let registry = test_scenario::take_shared<VerificationProviderRegistry>(&scenario);
            
            proof_of_creativity::request_verification(
                &poc,
                &profile,
                PROVIDER,
                &registry,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, poc);
            test_scenario::return_shared(registry);
        };
        
        // Check that the verification request exists
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let request = test_scenario::take_shared<VerificationRequest>(&scenario);
            test_scenario::return_shared(request);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_verify_proof() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create a clock for testing
        let clock = create_test_clock(&mut scenario);
        
        // Initialize the module to create the registry
        {
            proof_of_creativity::init_module(test_scenario::ctx(&mut scenario));
        };
        
        // Register a provider
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<VerificationProviderRegistry>(&scenario);
            
            proof_of_creativity::register_provider(
                &mut registry,
                PROVIDER,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // Create profiles for CREATOR and PROVIDER
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let creator_profile = create_test_profile(&mut scenario, b"Creator");
            mys::transfer::transfer(creator_profile, CREATOR);
        };
        
        test_scenario::next_tx(&mut scenario, PROVIDER);
        {
            let provider_profile = create_test_profile(&mut scenario, b"Provider");
            mys::transfer::transfer(provider_profile, PROVIDER);
        };
        
        // Create a proof of creativity
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            let title = string::utf8(b"My Creative Work");
            let description = string::utf8(b"This is a description of my creative work");
            let proof_type = PROOF_TYPE_TIMESTAMPED;
            let evidence_urls = vector[b"https://example.com/evidence.jpg"];
            let evidence_hash = b"0123456789abcdef";
            let references = vector[string::utf8(b"Inspiration 1")];
            let validators = vector[];
            
            proof_of_creativity::register_proof(
                &profile,
                title,
                description,
                proof_type,
                evidence_urls,
                evidence_hash,
                references,
                validators,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Request verification
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let poc = test_scenario::take_from_sender<ProofOfCreativity>(&scenario);
            let registry = test_scenario::take_shared<VerificationProviderRegistry>(&scenario);
            
            proof_of_creativity::request_verification(
                &poc,
                &profile,
                PROVIDER,
                &registry,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, poc);
            test_scenario::return_shared(registry);
        };
        
        // Provider verifies the proof
        test_scenario::next_tx(&mut scenario, PROVIDER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let poc = test_scenario::take_from_address<ProofOfCreativity>(&scenario, CREATOR);
            let request = test_scenario::take_shared<VerificationRequest>(&scenario);
            
            proof_of_creativity::verify_proof(
                &mut poc,
                &mut request,
                &profile,
                VERIFICATION_APPROVED,
                string::utf8(b"Looks good!"),
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify the proof is now verified
            assert!(proof_of_creativity::is_verified(&poc), 0);
            assert!(!proof_of_creativity::is_pending(&poc), 0);
            assert!(proof_of_creativity::verification_notes(&poc) == string::utf8(b"Looks good!"), 0);
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_address(CREATOR, poc);
            test_scenario::return_shared(request);
        };
        
        // Clean up the clock
        test_scenario::next_tx(&mut scenario, ADMIN);
        test_scenario::return_to_sender(&scenario, clock);
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_link_proof_to_ip() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create a clock for testing
        let clock = create_test_clock(&mut scenario);
        
        // Initialize the module to create the registry
        {
            proof_of_creativity::init_module(test_scenario::ctx(&mut scenario));
        };
        
        // Register a provider
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<VerificationProviderRegistry>(&scenario);
            
            proof_of_creativity::register_provider(
                &mut registry,
                PROVIDER,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // Create profiles for CREATOR and PROVIDER
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let creator_profile = create_test_profile(&mut scenario, b"Creator");
            mys::transfer::transfer(creator_profile, CREATOR);
        };
        
        test_scenario::next_tx(&mut scenario, PROVIDER);
        {
            let provider_profile = create_test_profile(&mut scenario, b"Provider");
            mys::transfer::transfer(provider_profile, PROVIDER);
        };
        
        // Create a proof of creativity
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            let title = string::utf8(b"My Creative Work");
            let description = string::utf8(b"This is a description of my creative work");
            let proof_type = PROOF_TYPE_TIMESTAMPED;
            let evidence_urls = vector[b"https://example.com/evidence.jpg"];
            let evidence_hash = b"0123456789abcdef";
            let references = vector[string::utf8(b"Inspiration 1")];
            let validators = vector[];
            
            proof_of_creativity::register_proof(
                &profile,
                title,
                description,
                proof_type,
                evidence_urls,
                evidence_hash,
                references,
                validators,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create an IP object
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let name = string::utf8(b"My IP Asset");
            let description = string::utf8(b"This is my intellectual property");
            
            let ip = my_ip::create(
                name,
                description,
                test_scenario::ctx(&mut scenario)
            );
            
            mys::transfer::transfer(ip, CREATOR);
        };
        
        // Request verification
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let poc = test_scenario::take_from_sender<ProofOfCreativity>(&scenario);
            let registry = test_scenario::take_shared<VerificationProviderRegistry>(&scenario);
            
            proof_of_creativity::request_verification(
                &poc,
                &profile,
                PROVIDER,
                &registry,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, poc);
            test_scenario::return_shared(registry);
        };
        
        // Provider verifies the proof
        test_scenario::next_tx(&mut scenario, PROVIDER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let poc = test_scenario::take_from_address<ProofOfCreativity>(&scenario, CREATOR);
            let request = test_scenario::take_shared<VerificationRequest>(&scenario);
            
            proof_of_creativity::verify_proof(
                &mut poc,
                &mut request,
                &profile,
                VERIFICATION_APPROVED,
                string::utf8(b"Looks good!"),
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_address(CREATOR, poc);
            test_scenario::return_shared(request);
        };
        
        // Link the proof to the IP
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let poc = test_scenario::take_from_sender<ProofOfCreativity>(&scenario);
            let ip = test_scenario::take_from_sender<MyIP>(&scenario);
            
            proof_of_creativity::link_proof_to_ip(
                &poc,
                &mut ip,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, poc);
            test_scenario::return_to_sender(&scenario, ip);
        };
        
        // Clean up the clock
        test_scenario::next_tx(&mut scenario, ADMIN);
        test_scenario::return_to_sender(&scenario, clock);
        
        test_scenario::end(scenario);
    }
}