// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
#[allow(unused_const)]
module social_contracts::profile_tests {
    use std::string;
    
    use mys::test_scenario;
    use social_contracts::profile::{Self, Profile, UsernameRegistry};
    use mys::url;
    use mys::coin::{Self, Coin};
    use mys::mys::MYS;
    use mys::clock;
    
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    
    #[test]
    fun test_create_profile_with_username() {
        let scenario = test_scenario::begin(ADMIN);
        {
            // Create test clock
            clock::create_for_testing(test_scenario::ctx(&mut scenario));
            
            // Mint coins for test
            let coins = coin::mint_for_testing<MYS>(20_000_000_000, test_scenario::ctx(&mut scenario));
            mys::transfer::transfer(coins, USER1);
        };
        
        // Create a profile with username
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let clock = test_scenario::take_shared<clock::Clock>(&scenario);
            let coins = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            
            // Create profile with username
            profile::create_profile_with_username(
                &mut registry,
                string::utf8(b"User One"),
                string::utf8(b"testname"),
                string::utf8(b"This is my bio"),
                b"https://example.com/image.png",
                b"",
                string::utf8(b"user@example.com"),
                &mut coins,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, coins);
        };
        
        // Check profile properties in the next transaction
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            // Check profile properties
            let display_name_opt = profile::display_name(&profile);
            assert!(std::option::is_some(&display_name_opt), 0);
            assert!(std::option::borrow(&display_name_opt) == &string::utf8(b"User One"), 0);
            assert!(profile::bio(&profile) == string::utf8(b"This is my bio"), 0);
            assert!(profile::owner(&profile) == USER1, 0);
            
            // Check username
            let username_opt = profile::username(&profile);
            assert!(std::option::is_some(&username_opt), 0);
            assert!(std::option::extract(&username_opt) == string::utf8(b"testname"), 0);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_update_profile() {
        let scenario = test_scenario::begin(ADMIN);
        {
            // Create test clock
            clock::create_for_testing(test_scenario::ctx(&mut scenario));
            
            // Mint coins for test
            let coins = coin::mint_for_testing<MYS>(20_000_000_000, test_scenario::ctx(&mut scenario));
            mys::transfer::transfer(coins, USER1);
        };
        
        // Create a profile with username
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let clock = test_scenario::take_shared<clock::Clock>(&scenario);
            let coins = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            
            // Create profile with username
            profile::create_profile_with_username(
                &mut registry,
                string::utf8(b"Original Name"),
                string::utf8(b"username"),
                string::utf8(b"Original bio"),
                b"https://example.com/image.png",
                b"",
                string::utf8(b"user@example.com"),
                &mut coins,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, coins);
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
                b"https://example.com/new_cover.png",
                string::utf8(b"updated@example.com"),
                test_scenario::ctx(&mut scenario)
            );
            
            // Check updated properties
            let display_name_opt = profile::display_name(&profile);
            assert!(std::option::is_some(&display_name_opt), 0);
            assert!(std::option::borrow(&display_name_opt) == &string::utf8(b"Updated Name"), 0);
            assert!(profile::bio(&profile) == string::utf8(b"Updated bio"), 0);
            
            // Username should not be affected by update_profile
            let username_opt = profile::username(&profile);
            assert!(std::option::is_some(&username_opt), 0);
            assert!(std::option::extract(&username_opt) == string::utf8(b"username"), 0);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = profile::EUnauthorized)]
    fun test_unauthorized_update() {
        let scenario = test_scenario::begin(ADMIN);
        {
            // Create test clock
            clock::create_for_testing(test_scenario::ctx(&mut scenario));
            
            // Mint coins for test
            let coins = coin::mint_for_testing<MYS>(20_000_000_000, test_scenario::ctx(&mut scenario));
            mys::transfer::transfer(coins, USER1);
        };
        
        // Create a profile with username
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let clock = test_scenario::take_shared<clock::Clock>(&scenario);
            let coins = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            
            // Create profile with username
            profile::create_profile_with_username(
                &mut registry,
                string::utf8(b"User One"),
                string::utf8(b"myusername"),
                string::utf8(b"This is my bio"),
                b"https://example.com/image.png",
                b"",
                string::utf8(b"user@example.com"),
                &mut coins,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, coins);
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
                b"https://example.com/hacked_cover.png",
                string::utf8(b"hacked@example.com"),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_address(USER1, profile);
        };
        
        test_scenario::end(scenario);
    }
}