// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module mys::social_graph_tests {
    use mys::test_scenario::{Self, Scenario};
    use mys::test_utils;
    use mys::profile::{Self, Profile};
    use mys::social_graph::{Self, SocialGraph};
    use mys::tx_context;
    use mys::object::{Self, UID};
    use mys::url::{Self, Url};
    use std::string::{Self, String};
    use std::vector;

    const TEST_SENDER: address = @0xCAFE;
    const OTHER_USER: address = @0xFACE;
    const THIRD_USER: address = @0xBEEF;
    
    // Helper function to create a profile
    fun create_test_profile(scenario: &mut Scenario): Profile {
        let display_name = string::utf8(b"Test User");
        let bio = string::utf8(b"This is a test bio");
        let profile_picture = std::option::some(url::new_unsafe_from_bytes(b"https://example.com/profile.jpg"));
        
        profile::create_profile(
            display_name,
            bio,
            profile_picture,
            test_scenario::ctx(scenario)
        )
    }
    
    #[test]
    fun test_initialize_social_graph() {
        let scenario = test_scenario::begin(TEST_SENDER);
        
        // Initialize social graph
        {
            social_graph::initialize(test_scenario::ctx(&mut scenario));
        };
        
        // Verify social graph was created
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            let social_graph = test_scenario::take_shared<SocialGraph>(&scenario);
            
            // Verify the social graph exists
            assert!(social_graph::following_count(&social_graph, TEST_SENDER) == 0, 0);
            assert!(social_graph::follower_count(&social_graph, TEST_SENDER) == 0, 1);
            assert!(vector::length(&social_graph::get_following(&social_graph, TEST_SENDER)) == 0, 2);
            assert!(vector::length(&social_graph::get_followers(&social_graph, TEST_SENDER)) == 0, 3);
            
            test_scenario::return_shared(social_graph);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_follow_user() {
        let scenario = test_scenario::begin(TEST_SENDER);
        
        // Setup: create profile for TEST_SENDER
        let test_profile = create_test_profile(&mut scenario);
        mys::transfer::transfer(test_profile, TEST_SENDER);
        
        // Initialize social graph
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            social_graph::initialize(test_scenario::ctx(&mut scenario));
        };
        
        // Create profile for OTHER_USER
        test_scenario::next_tx(&mut scenario, OTHER_USER);
        {
            let other_profile = create_test_profile(&mut scenario);
            mys::transfer::transfer(other_profile, OTHER_USER);
        };
        
        // TEST_SENDER follows OTHER_USER
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let social_graph_obj = test_scenario::take_shared<SocialGraph>(&scenario);
            let other_profile_id = object::id_to_address(&object::new(&mut test_scenario::ctx(&mut scenario)));
            
            social_graph::follow(
                &mut social_graph_obj,
                &profile,
                other_profile_id,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(social_graph_obj);
        };
        
        // Verify TEST_SENDER is following other_profile_id
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let social_graph_obj = test_scenario::take_shared<SocialGraph>(&scenario);
            
            let profile_id = object::uid_to_address(profile::id(&profile));
            let following_count = social_graph::following_count(&social_graph_obj, profile_id);
            assert!(following_count == 1, 0);
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(social_graph_obj);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_unfollow_user() {
        let scenario = test_scenario::begin(TEST_SENDER);
        
        // Setup: create profile for TEST_SENDER
        let test_profile = create_test_profile(&mut scenario);
        mys::transfer::transfer(test_profile, TEST_SENDER);
        
        // Initialize social graph
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            social_graph::initialize(test_scenario::ctx(&mut scenario));
        };
        
        // Create profile for OTHER_USER
        test_scenario::next_tx(&mut scenario, OTHER_USER);
        {
            let other_profile = create_test_profile(&mut scenario);
            mys::transfer::transfer(other_profile, OTHER_USER);
        };
        
        // Get OTHER_USER profile ID
        let other_profile_id: address;
        test_scenario::next_tx(&mut scenario, OTHER_USER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            other_profile_id = object::uid_to_address(profile::id(&profile));
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // TEST_SENDER follows OTHER_USER
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let social_graph_obj = test_scenario::take_shared<SocialGraph>(&scenario);
            
            social_graph::follow(
                &mut social_graph_obj,
                &profile,
                other_profile_id,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(social_graph_obj);
        };
        
        // TEST_SENDER unfollows OTHER_USER
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let social_graph_obj = test_scenario::take_shared<SocialGraph>(&scenario);
            
            social_graph::unfollow(
                &mut social_graph_obj,
                &profile,
                other_profile_id,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(social_graph_obj);
        };
        
        // Verify TEST_SENDER is no longer following OTHER_USER
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let social_graph_obj = test_scenario::take_shared<SocialGraph>(&scenario);
            
            let profile_id = object::uid_to_address(profile::id(&profile));
            let following_count = social_graph::following_count(&social_graph_obj, profile_id);
            assert!(following_count == 0, 0);
            assert!(!social_graph::is_following(&social_graph_obj, profile_id, other_profile_id), 1);
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(social_graph_obj);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = social_graph::ECannotFollowSelf)]
    fun test_cannot_follow_self() {
        let scenario = test_scenario::begin(TEST_SENDER);
        
        // Setup: create profile for TEST_SENDER
        let test_profile = create_test_profile(&mut scenario);
        mys::transfer::transfer(test_profile, TEST_SENDER);
        
        // Initialize social graph
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            social_graph::initialize(test_scenario::ctx(&mut scenario));
        };
        
        // Get profile ID
        let profile_id: address;
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            profile_id = object::uid_to_address(profile::id(&profile));
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Try to follow self (should fail)
        test_scenario::next_tx(&mut scenario, TEST_SENDER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let social_graph_obj = test_scenario::take_shared<SocialGraph>(&scenario);
            
            social_graph::follow(
                &mut social_graph_obj,
                &profile,
                profile_id, // Trying to follow self
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(social_graph_obj);
        };
        
        test_scenario::end(scenario);
    }
}