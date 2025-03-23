// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
#[allow(unused_const)]
module social_contracts::profile_tests {
    use std::string;
    
    use mys::test_scenario;
    use social_contracts::profile::{Self, Profile};
    use mys::url;
    
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    
    #[test]
    fun test_create_profile() {
        let scenario = test_scenario::begin(USER1);
        {
            // Create a profile
            profile::create_profile(
                string::utf8(b"User One"),
                string::utf8(b"This is my bio"),
                b"https://example.com/image.png",
                test_scenario::ctx(&mut scenario)
            );
        };
        
        // Check profile exists in the next transaction
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            // Check profile properties again
            assert!(profile::display_name(&profile) == string::utf8(b"User One"), 0);
            assert!(profile::bio(&profile) == string::utf8(b"This is my bio"), 0);
            assert!(profile::owner(&profile) == USER1, 0);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_update_profile() {
        let scenario = test_scenario::begin(USER1);
        {
            // Create a profile
            profile::create_profile(
                string::utf8(b"User One"),
                string::utf8(b"Original bio"),
                b"https://example.com/image.png",
                test_scenario::ctx(&mut scenario)
            );
        };
        
        // Update the profile in the next transaction
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            profile::update_profile(
                &mut profile,
                string::utf8(b"Updated Name"),
                string::utf8(b"Updated bio"),
                b"https://example.com/new_image.png",
                test_scenario::ctx(&mut scenario)
            );
            
            // Check updated properties
            assert!(profile::display_name(&profile) == string::utf8(b"Updated Name"), 0);
            assert!(profile::bio(&profile) == string::utf8(b"Updated bio"), 0);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = profile::EUnauthorized)]
    fun test_unauthorized_update() {
        let scenario = test_scenario::begin(USER1);
        {
            // User1 creates a profile
            profile::create_profile(
                string::utf8(b"User One"),
                string::utf8(b"Original bio"),
                b"https://example.com/image.png",
                test_scenario::ctx(&mut scenario)
            );
        };
        
        // User2 tries to update User1's profile
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let profile = test_scenario::take_from_address<Profile>(&scenario, USER1);
            
            // This should fail with EUnauthorized
            profile::update_profile(
                &mut profile,
                string::utf8(b"Hacked Name"),
                string::utf8(b"Hacked bio"),
                b"https://example.com/hacked.png",
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_address(USER1, profile);
        };
        
        test_scenario::end(scenario);
    }
}