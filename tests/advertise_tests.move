// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
#[allow(unused_const)]
module mys::advertise_tests {
    use std::string::{Self, String};
    use std::vector;
    use std::option;
    
    use mys::test_scenario::{Self, Scenario};
    use mys::advertise::{Self, AdRegistry, Advertiser, Campaign, AdAdminCap};
    use mys::profile::{Self, Profile};
    use mys::post::{Self, Post};
    use mys::url;
    use mys::clock::{Self, Clock};
    use mys::tx_context;
    use mys::coin::{Self, Coin};
    use mys::mys::MYS;
    use mys::transfer;
    
    // Test addresses
    const ADMIN: address = @0xAD;
    const ADVERTISER: address = @0xA1;
    const USER: address = @0xB1;
    
    // Test constants
    const PLATFORM_FEE_BPS: u64 = 1000; // 10%
    const BASE_BUDGET: u64 = 100000000; // 100 MYS
    
    // Create and return a test profile
    fun create_test_profile(scenario: &mut Scenario, owner: address): Profile {
        test_scenario::next_tx(scenario, owner);
        
        let display_name = string::utf8(b"Test Profile");
        let bio = string::utf8(b"This is a test profile for ad testing");
        let profile_picture = option::some(url::new_unsafe_from_bytes(b"https://example.com/profile.png"));
        
        profile::create_profile(
            display_name,
            bio,
            profile_picture,
            test_scenario::ctx(scenario)
        )
    }
    
    // Create and return a test post
    fun create_test_post(scenario: &mut Scenario, owner: address, profile: &Profile): Post {
        test_scenario::next_tx(scenario, owner);
        
        post::create_post(
            profile,
            string::utf8(b"Test post content"),
            vector::empty<vector<u8>>(),
            test_scenario::ctx(scenario)
        )
    }
    
    // Create and return a test clock
    fun create_test_clock(scenario: &mut Scenario): Clock {
        test_scenario::next_tx(scenario, ADMIN);
        
        clock::create_for_testing(test_scenario::ctx(scenario))
    }
    
    // Create test MYS tokens
    fun create_test_tokens(scenario: &mut Scenario, amount: u64): Coin<MYS> {
        test_scenario::next_tx(scenario, ADMIN);
        
        coin::mint_for_testing<MYS>(
            amount,
            test_scenario::ctx(scenario)
        )
    }
    
    // Test initializing the advertise module
    #[test]
    fun test_init_module() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Module initialization is done automatically
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Verify the AdRegistry was created and shared
            assert!(test_scenario::has_most_recent_shared<AdRegistry>(), 0);
            
            // Verify the admin cap was transferred to ADMIN
            assert!(test_scenario::has_most_recent_for_address<AdAdminCap>(ADMIN), 0);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test registering an advertiser
    #[test]
    fun test_register_advertiser() {
        let scenario = test_scenario::begin(ADVERTISER);
        
        // Create a profile for the advertiser
        let profile = create_test_profile(&mut scenario, ADVERTISER);
        transfer::transfer(profile, ADVERTISER);
        
        // Register the advertiser
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            advertise::register_advertiser(
                &mut registry,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Verify the advertiser was created
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            assert!(test_scenario::has_most_recent_shared<Advertiser>(), 0);
            
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            
            // Check advertiser properties
            let (total_spent, campaign_count, verified) = 
                advertise::get_advertiser_stats(&advertiser);
            
            assert!(total_spent == 0, 0);
            assert!(campaign_count == 0, 0);
            assert!(!verified, 0);
            
            test_scenario::return_shared(advertiser);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test creating a campaign
    #[test]
    fun test_create_campaign() {
        let scenario = test_scenario::begin(ADMIN);
        let clock = create_test_clock(&mut scenario);
        transfer::share_object(clock);
        
        // Create a profile and register as advertiser
        let profile = create_test_profile(&mut scenario, ADVERTISER);
        transfer::transfer(profile, ADVERTISER);
        
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            advertise::register_advertiser(
                &mut registry,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create a test post
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = create_test_post(&mut scenario, ADVERTISER, &profile);
            
            transfer::transfer(post, ADVERTISER);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create MYS tokens for payment
        let payment = create_test_tokens(&mut scenario, BASE_BUDGET * 2);
        transfer::public_transfer(payment, ADVERTISER);
        
        // Create the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_from_sender<Post>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 3600; // Start in 1 hour
            let duration = 86400 * 7; // Run for 7 days
            
            advertise::create_campaign(
                &mut registry,
                &mut advertiser,
                string::utf8(b"Test Campaign"),
                &post,
                0, // AD_FORMAT_FEED
                0, // AD_OBJECTIVE_ENGAGEMENT
                start_time,
                duration,
                BASE_BUDGET,
                1000000, // 1 MYS per engagement
                1, // BID_MODEL_CPC
                vector::empty<u8>(), // No targeting
                vector::empty<String>(), // No targeting values
                &mut payment,
                string::utf8(b"Test Ad Title"),
                string::utf8(b"Test Ad Content"),
                b"https://example.com/ad_image.png",
                string::utf8(b"Click Here"),
                b"https://example.com/destination",
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, post);
            test_scenario::return_to_sender(&scenario, payment);
        };
        
        // Verify the campaign was created
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            assert!(test_scenario::has_most_recent_shared<Campaign>(), 0);
            
            let campaign = test_scenario::take_shared<Campaign>(&scenario);
            
            // Check campaign properties
            let status = advertise::get_campaign_status(&campaign);
            let (total_budget, remaining_budget) = advertise::get_campaign_budgets(&campaign);
            let (impressions, clicks, engagements, conversions) = advertise::get_campaign_metrics(&campaign);
            
            assert!(status == 0, 0); // CAMPAIGN_STATUS_DRAFT
            assert!(total_budget == (BASE_BUDGET - (BASE_BUDGET * PLATFORM_FEE_BPS / 10000)), 0);
            assert!(remaining_budget == total_budget, 0);
            assert!(impressions == 0, 0);
            assert!(clicks == 0, 0);
            assert!(engagements == 0, 0);
            assert!(conversions == 0, 0);
            
            test_scenario::return_shared(campaign);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test activating a campaign
    #[test]
    fun test_activate_campaign() {
        let scenario = test_scenario::begin(ADMIN);
        let clock = create_test_clock(&mut scenario);
        transfer::share_object(clock);
        
        // Create a profile and register as advertiser
        let profile = create_test_profile(&mut scenario, ADVERTISER);
        transfer::transfer(profile, ADVERTISER);
        
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            advertise::register_advertiser(
                &mut registry,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create a test post
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = create_test_post(&mut scenario, ADVERTISER, &profile);
            
            transfer::transfer(post, ADVERTISER);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create MYS tokens for payment
        let payment = create_test_tokens(&mut scenario, BASE_BUDGET * 2);
        transfer::public_transfer(payment, ADVERTISER);
        
        // Create the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_from_sender<Post>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 3600; // Start in 1 hour
            let duration = 86400 * 7; // Run for 7 days
            
            advertise::create_campaign(
                &mut registry,
                &mut advertiser,
                string::utf8(b"Test Campaign"),
                &post,
                0, // AD_FORMAT_FEED
                0, // AD_OBJECTIVE_ENGAGEMENT
                start_time,
                duration,
                BASE_BUDGET,
                1000000, // 1 MYS per engagement
                1, // BID_MODEL_CPC
                vector::empty<u8>(), // No targeting
                vector::empty<String>(), // No targeting values
                &mut payment,
                string::utf8(b"Test Ad Title"),
                string::utf8(b"Test Ad Content"),
                b"https://example.com/ad_image.png",
                string::utf8(b"Click Here"),
                b"https://example.com/destination",
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, post);
            test_scenario::return_to_sender(&scenario, payment);
        };
        
        // Activate the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let campaign = test_scenario::take_shared<Campaign>(&scenario);
            
            advertise::activate_campaign(
                &registry,
                &advertiser,
                &mut campaign,
                test_scenario::ctx(&mut scenario)
            );
            
            // Check the campaign is now active
            assert!(advertise::get_campaign_status(&campaign) == 1, 0); // CAMPAIGN_STATUS_ACTIVE
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(campaign);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test pausing a campaign
    #[test]
    fun test_pause_campaign() {
        let scenario = test_scenario::begin(ADMIN);
        let clock = create_test_clock(&mut scenario);
        transfer::share_object(clock);
        
        // Create a profile and register as advertiser
        let profile = create_test_profile(&mut scenario, ADVERTISER);
        transfer::transfer(profile, ADVERTISER);
        
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            advertise::register_advertiser(
                &mut registry,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create a test post
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = create_test_post(&mut scenario, ADVERTISER, &profile);
            
            transfer::transfer(post, ADVERTISER);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create MYS tokens for payment
        let payment = create_test_tokens(&mut scenario, BASE_BUDGET * 2);
        transfer::public_transfer(payment, ADVERTISER);
        
        // Create and activate the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_from_sender<Post>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 3600; // Start in 1 hour
            let duration = 86400 * 7; // Run for 7 days
            
            advertise::create_campaign(
                &mut registry,
                &mut advertiser,
                string::utf8(b"Test Campaign"),
                &post,
                0, // AD_FORMAT_FEED
                0, // AD_OBJECTIVE_ENGAGEMENT
                start_time,
                duration,
                BASE_BUDGET,
                1000000, // 1 MYS per engagement
                1, // BID_MODEL_CPC
                vector::empty<u8>(), // No targeting
                vector::empty<String>(), // No targeting values
                &mut payment,
                string::utf8(b"Test Ad Title"),
                string::utf8(b"Test Ad Content"),
                b"https://example.com/ad_image.png",
                string::utf8(b"Click Here"),
                b"https://example.com/destination",
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            // Now activate the campaign
            let campaign = test_scenario::take_shared<Campaign>(&scenario);
            
            advertise::activate_campaign(
                &registry,
                &advertiser,
                &mut campaign,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(campaign);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, post);
            test_scenario::return_to_sender(&scenario, payment);
        };
        
        // Pause the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let campaign = test_scenario::take_shared<Campaign>(&scenario);
            
            advertise::pause_campaign(
                &registry,
                &advertiser,
                &mut campaign,
                test_scenario::ctx(&mut scenario)
            );
            
            // Check the campaign is now paused
            assert!(advertise::get_campaign_status(&campaign) == 2, 0); // CAMPAIGN_STATUS_PAUSED
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(campaign);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test canceling a campaign
    #[test]
    fun test_cancel_campaign() {
        let scenario = test_scenario::begin(ADMIN);
        let clock = create_test_clock(&mut scenario);
        transfer::share_object(clock);
        
        // Create a profile and register as advertiser
        let profile = create_test_profile(&mut scenario, ADVERTISER);
        transfer::transfer(profile, ADVERTISER);
        
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            advertise::register_advertiser(
                &mut registry,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create a test post
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = create_test_post(&mut scenario, ADVERTISER, &profile);
            
            transfer::transfer(post, ADVERTISER);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create MYS tokens for payment
        let payment = create_test_tokens(&mut scenario, BASE_BUDGET * 2);
        transfer::public_transfer(payment, ADVERTISER);
        
        // Create and activate the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_from_sender<Post>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 3600; // Start in 1 hour
            let duration = 86400 * 7; // Run for 7 days
            
            advertise::create_campaign(
                &mut registry,
                &mut advertiser,
                string::utf8(b"Test Campaign"),
                &post,
                0, // AD_FORMAT_FEED
                0, // AD_OBJECTIVE_ENGAGEMENT
                start_time,
                duration,
                BASE_BUDGET,
                1000000, // 1 MYS per engagement
                1, // BID_MODEL_CPC
                vector::empty<u8>(), // No targeting
                vector::empty<String>(), // No targeting values
                &mut payment,
                string::utf8(b"Test Ad Title"),
                string::utf8(b"Test Ad Content"),
                b"https://example.com/ad_image.png",
                string::utf8(b"Click Here"),
                b"https://example.com/destination",
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, post);
            test_scenario::return_to_sender(&scenario, payment);
        };
        
        // Cancel the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let campaign = test_scenario::take_shared<Campaign>(&scenario);
            
            advertise::cancel_campaign(
                &mut registry,
                &mut advertiser,
                &mut campaign,
                test_scenario::ctx(&mut scenario)
            );
            
            // Check the campaign is now cancelled
            assert!(advertise::get_campaign_status(&campaign) == 4, 0); // CAMPAIGN_STATUS_CANCELED
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(campaign);
        };
        
        // Verify refund was received
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            // There should be a refund coin sent to the advertiser
            assert!(test_scenario::has_most_recent_for_address<Coin<MYS>>(ADVERTISER), 0);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test funding a campaign
    #[test]
    fun test_fund_campaign() {
        let scenario = test_scenario::begin(ADMIN);
        let clock = create_test_clock(&mut scenario);
        transfer::share_object(clock);
        
        // Create a profile and register as advertiser
        let profile = create_test_profile(&mut scenario, ADVERTISER);
        transfer::transfer(profile, ADVERTISER);
        
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            advertise::register_advertiser(
                &mut registry,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create a test post
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = create_test_post(&mut scenario, ADVERTISER, &profile);
            
            transfer::transfer(post, ADVERTISER);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create MYS tokens for initial payment and additional funding
        let payment = create_test_tokens(&mut scenario, BASE_BUDGET * 3);
        transfer::public_transfer(payment, ADVERTISER);
        
        // Create the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_from_sender<Post>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 3600; // Start in 1 hour
            let duration = 86400 * 7; // Run for 7 days
            
            advertise::create_campaign(
                &mut registry,
                &mut advertiser,
                string::utf8(b"Test Campaign"),
                &post,
                0, // AD_FORMAT_FEED
                0, // AD_OBJECTIVE_ENGAGEMENT
                start_time,
                duration,
                BASE_BUDGET,
                1000000, // 1 MYS per engagement
                1, // BID_MODEL_CPC
                vector::empty<u8>(), // No targeting
                vector::empty<String>(), // No targeting values
                &mut payment,
                string::utf8(b"Test Ad Title"),
                string::utf8(b"Test Ad Content"),
                b"https://example.com/ad_image.png",
                string::utf8(b"Click Here"),
                b"https://example.com/destination",
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, post);
            test_scenario::return_to_sender(&scenario, payment);
        };
        
        // Get campaign budget before funding
        let (initial_total, initial_remaining) = (0, 0);
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let campaign = test_scenario::take_shared<Campaign>(&scenario);
            (initial_total, initial_remaining) = advertise::get_campaign_budgets(&campaign);
            test_scenario::return_shared(campaign);
        };
        
        // Add funds to the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let campaign = test_scenario::take_shared<Campaign>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            
            advertise::fund_campaign(
                &mut registry,
                &mut advertiser,
                &mut campaign,
                &mut payment,
                BASE_BUDGET, // Add BASE_BUDGET more
                test_scenario::ctx(&mut scenario)
            );
            
            // Check updated budgets
            let (new_total, new_remaining) = advertise::get_campaign_budgets(&campaign);
            
            // Calculate expected values after 10% platform fee
            let expected_increment = BASE_BUDGET - (BASE_BUDGET * PLATFORM_FEE_BPS / 10000);
            
            assert!(new_total == initial_total + expected_increment, 0);
            assert!(new_remaining == initial_remaining + expected_increment, 0);
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(campaign);
            test_scenario::return_to_sender(&scenario, payment);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test admin functions - set advertiser verification
    #[test]
    fun test_set_advertiser_verification() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create a profile and register as advertiser
        let profile = create_test_profile(&mut scenario, ADVERTISER);
        transfer::transfer(profile, ADVERTISER);
        
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            advertise::register_advertiser(
                &mut registry,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Verify the advertiser starts unverified
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let (_, _, verified) = advertise::get_advertiser_stats(&advertiser);
            assert!(!verified, 0);
            test_scenario::return_shared(advertiser);
        };
        
        // ADMIN verifies the advertiser
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdAdminCap>(&scenario);
            
            advertise::set_advertiser_verification(
                &registry,
                &admin_cap,
                &mut advertiser,
                true,
                test_scenario::ctx(&mut scenario)
            );
            
            // Check advertiser is now verified
            let (_, _, verified) = advertise::get_advertiser_stats(&advertiser);
            assert!(verified, 0);
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test admin function - withdraw platform fees
    #[test]
    fun test_withdraw_platform_fees() {
        let scenario = test_scenario::begin(ADMIN);
        let clock = create_test_clock(&mut scenario);
        transfer::share_object(clock);
        
        // Create a profile and register as advertiser
        let profile = create_test_profile(&mut scenario, ADVERTISER);
        transfer::transfer(profile, ADVERTISER);
        
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            advertise::register_advertiser(
                &mut registry,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create a test post
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = create_test_post(&mut scenario, ADVERTISER, &profile);
            
            transfer::transfer(post, ADVERTISER);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create MYS tokens for payment
        let payment = create_test_tokens(&mut scenario, BASE_BUDGET * 2);
        transfer::public_transfer(payment, ADVERTISER);
        
        // Create the campaign (which generates platform fees)
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_from_sender<Post>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 3600; // Start in 1 hour
            let duration = 86400 * 7; // Run for 7 days
            
            advertise::create_campaign(
                &mut registry,
                &mut advertiser,
                string::utf8(b"Test Campaign"),
                &post,
                0, // AD_FORMAT_FEED
                0, // AD_OBJECTIVE_ENGAGEMENT
                start_time,
                duration,
                BASE_BUDGET,
                1000000, // 1 MYS per engagement
                1, // BID_MODEL_CPC
                vector::empty<u8>(), // No targeting
                vector::empty<String>(), // No targeting values
                &mut payment,
                string::utf8(b"Test Ad Title"),
                string::utf8(b"Test Ad Content"),
                b"https://example.com/ad_image.png",
                string::utf8(b"Click Here"),
                b"https://example.com/destination",
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, post);
            test_scenario::return_to_sender(&scenario, payment);
        };
        
        // Admin withdraws the platform fees
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdAdminCap>(&scenario);
            
            advertise::withdraw_platform_fees(
                &mut registry,
                &admin_cap,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        
        // Verify admin received the platform fees
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            assert!(test_scenario::has_most_recent_for_address<Coin<MYS>>(ADMIN), 0);
            
            let fee_coin = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            // Expected fee is 10% of BASE_BUDGET
            let expected_fee = BASE_BUDGET * PLATFORM_FEE_BPS / 10000;
            assert!(coin::value(&fee_coin) == expected_fee, 0);
            
            test_scenario::return_to_sender(&scenario, fee_coin);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test recording an ad engagement
    #[test]
    fun test_record_engagement() {
        let scenario = test_scenario::begin(ADMIN);
        let clock = create_test_clock(&mut scenario);
        transfer::share_object(clock);
        
        // Create a profile and register as advertiser
        let profile = create_test_profile(&mut scenario, ADVERTISER);
        transfer::transfer(profile, ADVERTISER);
        
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            advertise::register_advertiser(
                &mut registry,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create a test post
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = create_test_post(&mut scenario, ADVERTISER, &profile);
            
            transfer::transfer(post, ADVERTISER);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create MYS tokens for payment
        let payment = create_test_tokens(&mut scenario, BASE_BUDGET * 2);
        transfer::public_transfer(payment, ADVERTISER);
        
        // Create and activate the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_from_sender<Post>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time; // Start immediately
            let duration = 86400 * 7; // Run for 7 days
            
            advertise::create_campaign(
                &mut registry,
                &mut advertiser,
                string::utf8(b"Test Campaign"),
                &post,
                0, // AD_FORMAT_FEED
                0, // AD_OBJECTIVE_ENGAGEMENT
                start_time,
                duration,
                BASE_BUDGET,
                1000000, // 1 MYS per engagement
                1, // BID_MODEL_CPC
                vector::empty<u8>(), // No targeting
                vector::empty<String>(), // No targeting values
                &mut payment,
                string::utf8(b"Test Ad Title"),
                string::utf8(b"Test Ad Content"),
                b"https://example.com/ad_image.png",
                string::utf8(b"Click Here"),
                b"https://example.com/destination",
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            // Now activate the campaign
            let campaign = test_scenario::take_shared<Campaign>(&scenario);
            
            advertise::activate_campaign(
                &registry,
                &advertiser,
                &mut campaign,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(campaign);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, post);
            test_scenario::return_to_sender(&scenario, payment);
        };
        
        // Record an engagement
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let campaign = test_scenario::take_shared<Campaign>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdAdminCap>(&scenario);
            
            // Get metrics before
            let (impressions_before, clicks_before, engagements_before, conversions_before) = 
                advertise::get_campaign_metrics(&campaign);
            
            // Record a click
            advertise::record_engagement(
                &registry,
                &admin_cap,
                &mut campaign,
                USER,
                1, // ENGAGEMENT_CLICK
                test_scenario::ctx(&mut scenario)
            );
            
            // Check metrics after
            let (impressions_after, clicks_after, engagements_after, conversions_after) = 
                advertise::get_campaign_metrics(&campaign);
            
            assert!(impressions_after == impressions_before, 0);
            assert!(clicks_after == clicks_before + 1, 0);
            assert!(engagements_after == engagements_before, 0);
            assert!(conversions_after == conversions_before, 0);
            
            // Verify an Engagement object was created
            assert!(test_scenario::has_most_recent_shared<Engagement>(), 0);
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(campaign);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test unauthorized campaign update (expected failure)
    #[test]
    #[expected_failure(abort_code = advertise::EUnauthorized)]
    fun test_unauthorized_campaign_update() {
        let scenario = test_scenario::begin(ADMIN);
        let clock = create_test_clock(&mut scenario);
        transfer::share_object(clock);
        
        // Create a profile and register as advertiser
        let profile = create_test_profile(&mut scenario, ADVERTISER);
        transfer::transfer(profile, ADVERTISER);
        
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            advertise::register_advertiser(
                &mut registry,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create a test post
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = create_test_post(&mut scenario, ADVERTISER, &profile);
            
            transfer::transfer(post, ADVERTISER);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Create MYS tokens for payment
        let payment = create_test_tokens(&mut scenario, BASE_BUDGET * 2);
        transfer::public_transfer(payment, ADVERTISER);
        
        // Create the campaign
        test_scenario::next_tx(&mut scenario, ADVERTISER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_from_sender<Post>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<MYS>>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 3600; // Start in 1 hour
            let duration = 86400 * 7; // Run for 7 days
            
            advertise::create_campaign(
                &mut registry,
                &mut advertiser,
                string::utf8(b"Test Campaign"),
                &post,
                0, // AD_FORMAT_FEED
                0, // AD_OBJECTIVE_ENGAGEMENT
                start_time,
                duration,
                BASE_BUDGET,
                1000000, // 1 MYS per engagement
                1, // BID_MODEL_CPC
                vector::empty<u8>(), // No targeting
                vector::empty<String>(), // No targeting values
                &mut payment,
                string::utf8(b"Test Ad Title"),
                string::utf8(b"Test Ad Content"),
                b"https://example.com/ad_image.png",
                string::utf8(b"Click Here"),
                b"https://example.com/destination",
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(clock);
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_to_sender(&scenario, post);
            test_scenario::return_to_sender(&scenario, payment);
        };
        
        // USER (not ADVERTISER) tries to activate the campaign - should fail
        test_scenario::next_tx(&mut scenario, USER);
        {
            let registry = test_scenario::take_shared<AdRegistry>(&scenario);
            let advertiser = test_scenario::take_shared<Advertiser>(&scenario);
            let campaign = test_scenario::take_shared<Campaign>(&scenario);
            
            // This should fail with EUnauthorized
            advertise::activate_campaign(
                &registry,
                &advertiser,
                &mut campaign,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(advertiser);
            test_scenario::return_shared(campaign);
        };
        
        test_scenario::end(scenario);
    }
}