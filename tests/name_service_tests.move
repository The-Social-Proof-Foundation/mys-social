// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
#[allow(unused_const, duplicate_alias)]
module social_contracts::name_service_tests {
    use std::string;
    
    use mys::test_scenario;
    use social_contracts::profile::{Self, Profile, UsernameRegistry};
    use mys::coin::{Self, Coin};
    use mys::mys::MYS;
    use mys::clock;
    use mys::object;
    
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    
    #[test]
    fun test_username_registry_creation() {
        let scenario = test_scenario::begin(ADMIN);
        {
            // Module initialization will create and share the registry automatically
        };
        
        // Check registry exists in the next transaction
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
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
        
        // Check profile has username in the next transaction
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Check profile has username
            assert!(profile::has_username(&profile), 0);
            let username_opt = profile::username(&profile);
            assert!(std::option::is_some(&username_opt), 0);
            assert!(std::option::extract(&username_opt) == string::utf8(b"testname"), 0);
            
            // Check registry mapping
            let profile_id = object::uid_to_address(profile::id(&profile));
            let lookup_result = profile::lookup_profile_by_username(&registry, string::utf8(b"testname"));
            assert!(std::option::is_some(&lookup_result), 0);
            assert!(std::option::extract(&lookup_result) == profile_id, 0);
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_change_username() {
        let scenario = test_scenario::begin(ADMIN);
        {
            // Create test clock
            clock::create_for_testing(test_scenario::ctx(&mut scenario));
            
            // Mint coins for test
            let coins = coin::mint_for_testing<MYS>(100_000_000_000, test_scenario::ctx(&mut scenario));
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
                string::utf8(b"oldname"),
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
        
        // Change username
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let clock = test_scenario::take_shared<clock::Clock>(&scenario);
            let coins = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            // Change username
            profile::change_username(
                &mut registry,
                &mut profile,
                string::utf8(b"newname"),
                &mut coins,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, coins);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Check new username is set
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Check profile has new username
            assert!(profile::has_username(&profile), 0);
            let username_opt = profile::username(&profile);
            assert!(std::option::is_some(&username_opt), 0);
            assert!(std::option::extract(&username_opt) == string::utf8(b"newname"), 0);
            
            // Check old username is removed from registry
            let old_lookup = profile::lookup_profile_by_username(&registry, string::utf8(b"oldname"));
            assert!(std::option::is_none(&old_lookup), 0);
            
            // Check new username is in registry
            let new_lookup = profile::lookup_profile_by_username(&registry, string::utf8(b"newname"));
            assert!(std::option::is_some(&new_lookup), 0);
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_transfer_profile_with_new_username() {
        let scenario = test_scenario::begin(ADMIN);
        {
            // Create test clock
            clock::create_for_testing(test_scenario::ctx(&mut scenario));
            
            // Mint coins for test
            let coins = coin::mint_for_testing<MYS>(100_000_000_000, test_scenario::ctx(&mut scenario));
            mys::transfer::transfer(coins, USER1);
            
            let coins2 = coin::mint_for_testing<MYS>(100_000_000_000, test_scenario::ctx(&mut scenario));
            mys::transfer::transfer(coins2, USER2);
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
                string::utf8(b"user1"),
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
        
        // Transfer profile to USER2 with new username
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let clock = test_scenario::take_shared<clock::Clock>(&scenario);
            let coins = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            // First change username, then transfer the profile
            profile::change_username(
                &mut registry,
                &mut profile,
                string::utf8(b"user2"),
                &mut coins,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            // Transfer profile
            profile::transfer_profile(
                &mut registry,
                profile, // Pass by value, not reference
                USER2,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, coins);
            // Note: profile is consumed so no need to return it
        };
        
        // Check profile was transferred with new username
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Check profile ownership
            assert!(profile::owner(&profile) == USER2, 0);
            
            // Check profile has new username
            assert!(profile::has_username(&profile), 0);
            let username_opt = profile::username(&profile);
            assert!(std::option::is_some(&username_opt), 0);
            assert!(std::option::extract(&username_opt) == string::utf8(b"user2"), 0);
            
            // Check old username is removed from registry
            let old_lookup = profile::lookup_profile_by_username(&registry, string::utf8(b"user1"));
            assert!(std::option::is_none(&old_lookup), 0);
            
            // Check new username is in registry
            let new_lookup = profile::lookup_profile_by_username(&registry, string::utf8(b"user2"));
            assert!(std::option::is_some(&new_lookup), 0);
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_renew_username() {
        let scenario = test_scenario::begin(ADMIN);
        {
            // Create test clock
            clock::create_for_testing(test_scenario::ctx(&mut scenario));
            
            // Mint coins for test
            let coins = coin::mint_for_testing<MYS>(100_000_000_000, test_scenario::ctx(&mut scenario));
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
                string::utf8(b"renewme"),
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
        
        // Get original expiry
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            // Check original expiry
            let expiry_opt = profile::username_expiry(&profile);
            assert!(std::option::is_some(&expiry_opt), 0);
            let original_expiry = std::option::extract(&expiry_opt);
            
            // Remember original expiry for later comparison
            test_scenario::ctx(&mut scenario).store(original_expiry);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Renew username
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let clock = test_scenario::take_shared<clock::Clock>(&scenario);
            let coins = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            // Renew for 6 more epochs
            profile::renew_username(
                &mut registry,
                &mut profile,
                6, 
                &mut coins,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, coins);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Check expiry was extended
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let original_expiry: u64 = test_scenario::ctx(&mut scenario).load();
            
            // Check new expiry
            let expiry_opt = profile::username_expiry(&profile);
            assert!(std::option::is_some(&expiry_opt), 0);
            let new_expiry = std::option::extract(&expiry_opt);
            
            // New expiry should be greater than original
            assert!(new_expiry > original_expiry, 0);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        test_scenario::end(scenario);
    }
}