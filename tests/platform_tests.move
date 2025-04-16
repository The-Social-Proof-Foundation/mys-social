// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

#[test_only]
#[allow(unused_const, duplicate_alias, unused_use)]
module social_contracts::platform_tests {
    use std::string;
    use std::option;
    use std::vector;
    
    use mys::test_scenario;
    use mys::object;
    use mys::transfer;
    use mys::clock::{Self, Clock};
    
    use social_contracts::profile::{Self, Profile, UsernameRegistry};
    use social_contracts::platform::{Self, Platform, PlatformRegistry};
    
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    const USER3: address = @0x3;
    const PLATFORM_ADMIN: address = @0xF1;
    const PLATFORM_MOD: address = @0xF2;
    const PLATFORM_USER: address = @0xF3;
    
    // Helper function to create a test platform
    fun create_test_platform(scenario: &mut test_scenario::Scenario) {
        // Initialize the platform registry
        test_scenario::next_tx(scenario, ADMIN);
        {
            platform::test_init(test_scenario::ctx(scenario));
        };

        // Create a new platform in a separate transaction 
        test_scenario::next_tx(scenario, PLATFORM_ADMIN);
        {
            let mut registry = test_scenario::take_shared<PlatformRegistry>(scenario);
            
            // Create platform
            platform::create_platform(
                &mut registry,
                string::utf8(b"Test Platform"),
                string::utf8(b"A test platform"),
                string::utf8(b"This is a test platform for badge testing"),
                string::utf8(b"https://example.com/logo.png"),
                string::utf8(b"https://example.com/terms"),
                string::utf8(b"https://example.com/privacy"),
                vector[string::utf8(b"web"), string::utf8(b"mobile")],
                vector[string::utf8(b"https://example.com")],
                2, // STATUS_BETA
                string::utf8(b"2023-01-01"),
                true, // wants_dao_governance
                option::some(7), // delegate_count
                option::some(30), // delegate_term_epochs
                option::some(50_000_000), // proposal_submission_cost
                option::some(7), // min_on_chain_age_days
                option::some(5), // max_votes_per_user
                option::some(5_000_000), // quadratic_base_cost
                option::some(3), // voting_period_epochs
                option::some(15), // quorum_votes
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(registry);
        };

        // Add moderator to platform
        test_scenario::next_tx(scenario, PLATFORM_ADMIN);
        {
            let mut platform = test_scenario::take_from_sender<Platform>(scenario);
            
            platform::add_moderator(
                &mut platform,
                PLATFORM_MOD,
                test_scenario::ctx(scenario)
            );
            
            // Set platform as approved
            platform::test_set_approval(&mut platform, true);
            
            test_scenario::return_to_sender(scenario, platform);
        };
    }

    // Helper function to create a test profile
    fun create_test_profile(scenario: &mut test_scenario::Scenario, owner: address, username: string::String) {
        // Make sure profile registry is initialized first
        if (!test_scenario::has_most_recent_shared<UsernameRegistry>()) {
            test_scenario::next_tx(scenario, ADMIN);
            {
                profile::init_for_testing(test_scenario::ctx(scenario));
            };
        };
        
        // Now create the profile
        test_scenario::next_tx(scenario, owner);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(scenario);
            
            // Create profile
            profile::create_profile(
                &mut registry,
                string::utf8(b"Test User"),
                username,
                string::utf8(b"This is a test profile for badges"),
                b"https://example.com/avatar.png",
                b"",
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(registry);
        };
    }
    
    #[test]
    fun test_platform_admin_assigns_badge() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize the clock first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Create test clock
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(clock);
        };
        
        // Create platform and profile
        create_test_platform(&mut scenario);
        create_test_profile(&mut scenario, PLATFORM_USER, string::utf8(b"platform_user"));
        
        // Platform admin assigns a badge to the user's profile
        test_scenario::next_tx(&mut scenario, PLATFORM_ADMIN);
        {
            let platform = test_scenario::take_from_sender<Platform>(&scenario);
            let mut user_profile = test_scenario::take_from_address<Profile>(&scenario, PLATFORM_USER);
            
            let badge_name = string::utf8(b"VIP");
            
            // Assign badge
            platform::assign_badge(
                &platform,
                &mut user_profile,
                badge_name,
                string::utf8(b"Very Important Person"),
                string::utf8(b"https://example.com/vip_badge.png"),
                10, // badge_type
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify badge was assigned
            let badges = profile::get_profile_badges(&user_profile);
            assert!(vector::length(&badges) == 1, 1);
            
            // Verify badge count
            assert!(profile::badge_count(&user_profile) == 1, 2);
            
            // Verify badge details
            let badge_id = string::utf8(b"badge_VIP");
            assert!(profile::has_badge(&user_profile, &badge_id), 3);
            
            let badge_opt = profile::get_badge(&user_profile, &badge_id);
            assert!(option::is_some(&badge_opt), 4);
            
            test_scenario::return_to_sender(&scenario, platform);
            test_scenario::return_to_address(PLATFORM_USER, user_profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_platform_mod_assigns_and_revokes_badge() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize the clock first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Create test clock
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(clock);
        };
        
        // Create platform and profile
        create_test_platform(&mut scenario);
        create_test_profile(&mut scenario, PLATFORM_USER, string::utf8(b"platform_user2"));
        
        // Platform moderator assigns a badge to the user's profile
        test_scenario::next_tx(&mut scenario, PLATFORM_MOD);
        {
            let platform = test_scenario::take_from_address<Platform>(&scenario, PLATFORM_ADMIN);
            let mut user_profile = test_scenario::take_from_address<Profile>(&scenario, PLATFORM_USER);
            
            let badge_name = string::utf8(b"Contributor");
            let badge_id = string::utf8(b"badge_Contributor");
            
            // Assign badge
            platform::assign_badge(
                &platform,
                &mut user_profile,
                badge_name,
                string::utf8(b"Active Contributor"),
                string::utf8(b"https://example.com/contributor_badge.png"),
                5, // badge_type
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify badge was assigned
            assert!(profile::badge_count(&user_profile) == 1, 1);
            assert!(profile::has_badge(&user_profile, &badge_id), 2);
            
            // Now revoke the badge
            platform::revoke_badge(
                &platform,
                &mut user_profile,
                badge_id,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify badge was revoked
            assert!(profile::badge_count(&user_profile) == 0, 3);
            assert!(!profile::has_badge(&user_profile, &badge_id), 4);
            
            test_scenario::return_to_address(PLATFORM_ADMIN, platform);
            test_scenario::return_to_address(PLATFORM_USER, user_profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_multiple_badges_from_platform() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize the clock first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Create test clock
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(clock);
        };
        
        // Create platform and profile
        create_test_platform(&mut scenario);
        create_test_profile(&mut scenario, PLATFORM_USER, string::utf8(b"platform_user3"));
        
        // Platform admin assigns multiple badges to the user's profile
        test_scenario::next_tx(&mut scenario, PLATFORM_ADMIN);
        {
            let platform = test_scenario::take_from_sender<Platform>(&scenario);
            let mut user_profile = test_scenario::take_from_address<Profile>(&scenario, PLATFORM_USER);
            
            // Create the platform ID for later comparisons
            let platform_id = object::uid_to_address(platform::id(&platform));
            
            // Assign first badge
            platform::assign_badge(
                &platform,
                &mut user_profile,
                string::utf8(b"VIP"),
                string::utf8(b"Very Important Person"),
                string::utf8(b"https://example.com/vip_badge.png"),
                10, // badge_type
                test_scenario::ctx(&mut scenario)
            );
            
            // Assign second badge
            platform::assign_badge(
                &platform,
                &mut user_profile,
                string::utf8(b"Moderator"),
                string::utf8(b"Community Moderator"),
                string::utf8(b"https://example.com/mod_badge.png"),
                20, // badge_type
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify total badge count
            assert!(profile::badge_count(&user_profile) == 2, 1);
            
            // Verify all badges are from the same platform
            let platform_badges = profile::get_platform_badges(&user_profile, platform_id);
            assert!(vector::length(&platform_badges) == 2, 2);
            
            test_scenario::return_to_sender(&scenario, platform);
            test_scenario::return_to_address(PLATFORM_USER, user_profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = platform::EUnauthorized)]
    fun test_unauthorized_badge_assignment() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize the clock first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Create test clock
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(clock);
        };
        
        // Create platform and profile
        create_test_platform(&mut scenario);
        create_test_profile(&mut scenario, PLATFORM_USER, string::utf8(b"platform_user4"));
        
        // Normal user attempts to assign a badge (should fail)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let platform = test_scenario::take_from_address<Platform>(&scenario, PLATFORM_ADMIN);
            let mut user_profile = test_scenario::take_from_address<Profile>(&scenario, PLATFORM_USER);
            
            // This should fail with EUnauthorized since USER1 is neither platform admin nor moderator
            platform::assign_badge(
                &platform,
                &mut user_profile,
                string::utf8(b"Fake"),
                string::utf8(b"Fake Badge"),
                string::utf8(b"https://example.com/fake.png"),
                1,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_address(PLATFORM_ADMIN, platform);
            test_scenario::return_to_address(PLATFORM_USER, user_profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = profile::EBadgeAlreadyExists)]
    fun test_duplicate_badge_prevention() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize the clock first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Create test clock
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(clock);
        };
        
        // Create platform and profile
        create_test_platform(&mut scenario);
        create_test_profile(&mut scenario, PLATFORM_USER, string::utf8(b"platform_user5"));
        
        // Platform admin assigns a badge, then tries to assign the same badge again
        test_scenario::next_tx(&mut scenario, PLATFORM_ADMIN);
        {
            let platform = test_scenario::take_from_sender<Platform>(&scenario);
            let mut user_profile = test_scenario::take_from_address<Profile>(&scenario, PLATFORM_USER);
            
            let badge_name = string::utf8(b"VIP");
            
            // Assign badge first time - should succeed
            platform::assign_badge(
                &platform,
                &mut user_profile,
                badge_name,
                string::utf8(b"Very Important Person"),
                string::utf8(b"https://example.com/vip_badge.png"),
                10, // badge_type
                test_scenario::ctx(&mut scenario)
            );
            
            // Try to assign the same badge again - should fail
            platform::assign_badge(
                &platform,
                &mut user_profile,
                badge_name,
                string::utf8(b"Very Important Person"),
                string::utf8(b"https://example.com/vip_badge.png"),
                10, // badge_type
                test_scenario::ctx(&mut scenario)
            );
            
            // Not reached due to expected failure
            test_scenario::return_to_sender(&scenario, platform);
            test_scenario::return_to_address(PLATFORM_USER, user_profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = profile::EBadgeNotFound)]
    fun test_revoke_nonexistent_badge() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize the clock first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Create test clock
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(clock);
        };
        
        // Create platform and profile
        create_test_platform(&mut scenario);
        create_test_profile(&mut scenario, PLATFORM_USER, string::utf8(b"platform_user6"));
        
        // Platform admin tries to revoke a nonexistent badge
        test_scenario::next_tx(&mut scenario, PLATFORM_ADMIN);
        {
            let platform = test_scenario::take_from_sender<Platform>(&scenario);
            let mut user_profile = test_scenario::take_from_address<Profile>(&scenario, PLATFORM_USER);
            
            // Try to revoke a nonexistent badge - should fail
            platform::revoke_badge(
                &platform,
                &mut user_profile,
                string::utf8(b"badge_NonexistentBadge"),
                test_scenario::ctx(&mut scenario)
            );
            
            // Not reached due to expected failure
            test_scenario::return_to_sender(&scenario, platform);
            test_scenario::return_to_address(PLATFORM_USER, user_profile);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_badges_persist_through_profile_transfer() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize the clock first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Create test clock
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(clock);
        };
        
        // Create platform and profile
        create_test_platform(&mut scenario);
        create_test_profile(&mut scenario, PLATFORM_USER, string::utf8(b"platform_user7"));
        
        // Platform admin assigns a badge to the user's profile
        test_scenario::next_tx(&mut scenario, PLATFORM_ADMIN);
        {
            let platform = test_scenario::take_from_sender<Platform>(&scenario);
            let mut user_profile = test_scenario::take_from_address<Profile>(&scenario, PLATFORM_USER);
            
            // Assign badge
            platform::assign_badge(
                &platform,
                &mut user_profile,
                string::utf8(b"VIP"),
                string::utf8(b"Very Important Person"),
                string::utf8(b"https://example.com/vip_badge.png"),
                10, // badge_type
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify badge was assigned
            assert!(profile::badge_count(&user_profile) == 1, 1);
            
            test_scenario::return_to_sender(&scenario, platform);
            test_scenario::return_to_address(PLATFORM_USER, user_profile);
        };
        
        // PLATFORM_USER transfers profile to USER2
        test_scenario::next_tx(&mut scenario, PLATFORM_USER);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            // Transfer profile to USER2
            profile::transfer_profile(
                &mut registry,
                profile,
                USER2,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // Verify USER2 received the profile with badge intact
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            // Verify badge is still on the profile after transfer
            assert!(profile::badge_count(&profile) == 1, 2);
            assert!(profile::has_badge(&profile, &string::utf8(b"badge_VIP")), 3);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        test_scenario::end(scenario);
    }
} 