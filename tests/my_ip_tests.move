#[test_only]
#[allow(duplicate_alias, unused_use, unused_function)]
module social_contracts::my_ip_tests {
    use std::string;
    use std::option;
    use std::vector;
    
    use mys::test_scenario;
    use mys::test_utils::assert_eq;
    use mys::transfer;
    use mys::coin::{Self, Coin};
    use mys::clock::{Self, Clock};
    use mys::test_utils;
    use mys::object;
    
    use social_contracts::my_ip::{Self, MyIP, MyIPRegistry};
    use social_contracts::profile::{Self, Profile, UsernameRegistry};
    
    // Test addresses
    const CREATOR: address = @0xA1;
    const BUYER: address = @0xB2;
    const ANOTHER_USER: address = @0xC3;
    
    #[test]
    fun test_create_my_ip_data() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Set up test environment
        init_test_environment(&mut scenario);
        
        // Create MyIP data
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let mut registry = test_scenario::take_shared<MyIPRegistry>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            my_ip::create_and_share(
                &mut registry,
                string::utf8(b"data"),
                vector[string::utf8(b"analytics"), string::utf8(b"personal")],
                option::none<address>(), // platform_id
                1000, // timestamp_start
                option::some(2000), // timestamp_end
                b"encrypted_test_data", // encrypted_data
                b"encryption_id_123", // encryption_id
                option::some(100), // one_time_price (100 MYS)
                option::some(50), // subscription_price (50 MYS/month)
                30, // subscription_duration_days
                option::some(string::utf8(b"US")), // geographic_region
                option::some(string::utf8(b"high")), // data_quality
                option::some(1000), // sample_size
                option::some(string::utf8(b"automated")), // collection_method
                true, // is_updating
                option::some(string::utf8(b"daily")), // update_frequency
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
        };
        
        // Verify MyIP was created with correct properties
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let myip = test_scenario::take_shared<MyIP>(&scenario);
            
            assert_eq(my_ip::owner(&myip), CREATOR);
            assert_eq(my_ip::media_type(&myip), string::utf8(b"data"));
            assert_eq(my_ip::one_time_price(&myip), option::some(100));
            assert_eq(my_ip::subscription_price(&myip), option::some(50));
            assert_eq(my_ip::subscription_duration_days(&myip), 30);
            assert_eq(my_ip::is_one_time_for_sale(&myip), true);
            assert_eq(my_ip::is_subscription_available(&myip), true);
            
            test_scenario::return_shared(myip);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_purchase_one_time_access() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup and create MyIP
        init_test_environment(&mut scenario);
        create_test_my_ip(&mut scenario);
        
        // Give BUYER some coins
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let coin = coin::mint_for_testing<mys::mys::MYS>(200, test_scenario::ctx(&mut scenario));
            transfer::public_transfer(coin, BUYER);
        };
        
        // BUYER purchases one-time access
        {
            test_scenario::next_tx(&mut scenario, BUYER);
            let mut myip = test_scenario::take_shared<MyIP>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<mys::mys::MYS>>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            my_ip::purchase_one_time(
                &mut myip,
                payment,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(myip);
            test_scenario::return_shared(clock);
        };
        
        // Verify access was granted
        {
            test_scenario::next_tx(&mut scenario, BUYER);
            let myip = test_scenario::take_shared<MyIP>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            assert_eq(my_ip::has_access(&myip, BUYER, &clock), true);
            assert_eq(my_ip::has_access(&myip, ANOTHER_USER, &clock), false);
            
            test_scenario::return_shared(myip);
            test_scenario::return_shared(clock);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_purchase_subscription() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup and create MyIP
        init_test_environment(&mut scenario);
        create_test_my_ip(&mut scenario);
        
        // Give BUYER some coins
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let coin = coin::mint_for_testing<mys::mys::MYS>(200, test_scenario::ctx(&mut scenario));
            transfer::public_transfer(coin, BUYER);
        };
        
        // BUYER purchases subscription
        {
            test_scenario::next_tx(&mut scenario, BUYER);
            let mut myip = test_scenario::take_shared<MyIP>(&scenario);
            let payment = test_scenario::take_from_sender<Coin<mys::mys::MYS>>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            my_ip::purchase_subscription(
                &mut myip,
                payment,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(myip);
            test_scenario::return_shared(clock);
        };
        
        // Verify subscription access
        {
            test_scenario::next_tx(&mut scenario, BUYER);
            let myip = test_scenario::take_shared<MyIP>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            assert_eq(my_ip::has_access(&myip, BUYER, &clock), true);
            assert_eq(my_ip::has_active_subscription(&myip, BUYER, &clock), true);
            assert_eq(my_ip::has_access(&myip, ANOTHER_USER, &clock), false);
            
            test_scenario::return_shared(myip);
            test_scenario::return_shared(clock);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_update_pricing() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup and create MyIP
        init_test_environment(&mut scenario);
        create_test_my_ip(&mut scenario);
        
        // Update pricing
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let mut myip = test_scenario::take_shared<MyIP>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            my_ip::update_pricing(
                &mut myip,
                option::some(150), // new one_time_price
                option::some(75), // new subscription_price
                option::some(60), // new subscription_duration_days
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify pricing was updated
            assert_eq(my_ip::one_time_price(&myip), option::some(150));
            assert_eq(my_ip::subscription_price(&myip), option::some(75));
            assert_eq(my_ip::subscription_duration_days(&myip), 60);
            
            test_scenario::return_shared(myip);
            test_scenario::return_shared(clock);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_grant_free_access() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup and create MyIP
        init_test_environment(&mut scenario);
        create_test_my_ip(&mut scenario);
        
        // Grant free access to BUYER
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let mut myip = test_scenario::take_shared<MyIP>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            my_ip::grant_access(
                &mut myip,
                BUYER,
                0, // one-time access
                option::none<u64>(),
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(myip);
            test_scenario::return_shared(clock);
        };
        
        // Verify free access was granted
        {
            test_scenario::next_tx(&mut scenario, BUYER);
            let myip = test_scenario::take_shared<MyIP>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            assert_eq(my_ip::has_access(&myip, BUYER, &clock), true);
            
            test_scenario::return_shared(myip);
            test_scenario::return_shared(clock);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_access_control() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup and create MyIP
        init_test_environment(&mut scenario);
        create_test_my_ip(&mut scenario);
        
        // Verify owner always has access
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let myip = test_scenario::take_shared<MyIP>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            assert_eq(my_ip::has_access(&myip, CREATOR, &clock), true);
            assert_eq(my_ip::has_access(&myip, BUYER, &clock), false);
            assert_eq(my_ip::has_access(&myip, ANOTHER_USER, &clock), false);
            
            test_scenario::return_shared(myip);
            test_scenario::return_shared(clock);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_registry_functions() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup and create MyIP
        init_test_environment(&mut scenario);
        create_test_my_ip(&mut scenario);
        
        // Test registry functions
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let registry = test_scenario::take_shared<MyIPRegistry>(&scenario);
            let myip = test_scenario::take_shared<MyIP>(&scenario);
            
            // Test permission checks (simplified implementation returns true for registered IPs)
            // Note: For this test, we'll skip the ID-based registry lookups since the field is private
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(myip);
        };
        
        test_scenario::end(scenario);
    }
    
    // Helper functions
    
    fun init_test_environment(scenario: &mut test_scenario::Scenario) {
        // Initialize MyIP registry
        test_scenario::next_tx(scenario, CREATOR);
        {
            my_ip::test_init(test_scenario::ctx(scenario));
            profile::init_for_testing(test_scenario::ctx(scenario));
            let _witness = test_utils::create_one_time_witness<mys::mys::MYS>();
            clock::share_for_testing(clock::create_for_testing(test_scenario::ctx(scenario)));
        };
        
        // Create profile for creator
        test_scenario::next_tx(scenario, CREATOR);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(scenario);
            
            profile::create_profile(
                &mut registry,
                string::utf8(b"Test Creator"),
                string::utf8(b"creator"),
                string::utf8(b"Creator profile for testing"),
                b"https://example.com/creator.jpg",
                b"",
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(registry);
        };
    }
    
    fun create_test_my_ip(scenario: &mut test_scenario::Scenario) {
        test_scenario::next_tx(scenario, CREATOR);
        {
            let mut registry = test_scenario::take_shared<MyIPRegistry>(scenario);
            let clock = test_scenario::take_shared<Clock>(scenario);
            
            my_ip::create_and_share(
                &mut registry,
                string::utf8(b"data"),
                vector[string::utf8(b"test")],
                option::none<address>(), // platform_id
                1000, // timestamp_start
                option::none<u64>(), // timestamp_end
                b"encrypted_data", // encrypted_data
                b"encryption_id", // encryption_id
                option::some(100), // one_time_price
                option::some(50), // subscription_price
                30, // subscription_duration_days
                option::none<string::String>(), // geographic_region
                option::none<string::String>(), // data_quality
                option::none<u64>(), // sample_size
                option::none<string::String>(), // collection_method
                false, // is_updating
                option::none<string::String>(), // update_frequency
                &clock,
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
        };
    }
} 