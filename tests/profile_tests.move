// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

#[test_only]
#[allow(unused_const, duplicate_alias, unused_use)]
module social_contracts::profile_tests {
    use std::string;
    use std::option;
    
    use mys::test_scenario;
    use social_contracts::profile::{Self, Profile, UsernameRegistry};
    use mys::url;
    use mys::coin::{Self, Coin};
    use mys::mys::MYS;
    use mys::clock::{Self, Clock};
    use mys::transfer;
    
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    
    #[test]
    fun test_create_profile() {
        let mut scenario = test_scenario::begin(ADMIN);
        {
            // Initialize the UsernameRegistry
            profile::init_for_testing(test_scenario::ctx(&mut scenario));
            
            // Create test clock and share it using the correct approach
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(clock);
            
            // Mint coins for test
            let coins = coin::mint_for_testing<MYS>(20_000_000_000, test_scenario::ctx(&mut scenario));
            transfer::public_transfer(coins, USER1);
        };
        
        // Create a profile
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            // Create profile
            profile::create_profile(
                &mut registry,
                string::utf8(b"User One"),
                string::utf8(b"testname"),
                string::utf8(b"This is my bio"),
                b"https://example.com/image.png",
                b"",
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
        };
        
        // Check profile properties in the next transaction
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            // Check profile properties
            let display_name_opt = profile::display_name(&profile);
            assert!(option::is_some(&display_name_opt), 0);
            assert!(option::borrow(&display_name_opt) == &string::utf8(b"User One"), 0);
            assert!(profile::bio(&profile) == string::utf8(b"This is my bio"), 0);
            assert!(profile::owner(&profile) == USER1, 0);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_update_profile() {
        let mut scenario = test_scenario::begin(ADMIN);
        {
            // Initialize the UsernameRegistry
            profile::init_for_testing(test_scenario::ctx(&mut scenario));
            
            // Create test clock and share it using the correct approach
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(clock);
            
            // Mint coins for test
            let coins = coin::mint_for_testing<MYS>(20_000_000_000, test_scenario::ctx(&mut scenario));
            transfer::public_transfer(coins, USER1);
        };
        
        // Create a profile
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            // Create profile
            profile::create_profile(
                &mut registry,
                string::utf8(b"Original Name"),
                string::utf8(b"username"),
                string::utf8(b"Original bio"),
                b"https://example.com/image.png",
                b"",
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
        };
        
        // Update the profile in the next transaction
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            profile::update_profile(
                &mut profile,
                string::utf8(b"Updated Name"),
                string::utf8(b"Updated bio"),
                b"https://example.com/new_image.png",
                b"https://example.com/new_cover.png",
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            // Check updated properties
            let display_name_opt = profile::display_name(&profile);
            assert!(option::is_some(&display_name_opt), 0);
            assert!(option::borrow(&display_name_opt) == &string::utf8(b"Updated Name"), 0);
            assert!(profile::bio(&profile) == string::utf8(b"Updated bio"), 0);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = profile::EUnauthorized, location = social_contracts::profile)]
    fun test_unauthorized_update() {
        let mut scenario = test_scenario::begin(ADMIN);
        {
            // Initialize the UsernameRegistry
            profile::init_for_testing(test_scenario::ctx(&mut scenario));
            
            // Create test clock and share it using the correct approach
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(clock);
            
            // Mint coins for test
            let coins = coin::mint_for_testing<MYS>(20_000_000_000, test_scenario::ctx(&mut scenario));
            transfer::public_transfer(coins, USER1);
        };
        
        // Create a profile
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            // Create profile
            profile::create_profile(
                &mut registry,
                string::utf8(b"User One"),
                string::utf8(b"myusername"),
                string::utf8(b"This is my bio"),
                b"https://example.com/image.png",
                b"",
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
        };
        
        // User2 tries to update User1's profile
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let mut profile = test_scenario::take_from_address<Profile>(&scenario, USER1);
            
            // This should fail with EUnauthorized
            profile::update_profile(
                &mut profile,
                string::utf8(b"Hacked Name"),
                string::utf8(b"Hacked bio"),
                b"https://example.com/hacked.png",
                b"https://example.com/hacked_cover.png",
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_address(USER1, profile);
        };
        
        test_scenario::end(scenario);
    }
}