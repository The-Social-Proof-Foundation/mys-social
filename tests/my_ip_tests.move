#[test_only]
#[allow(duplicate_alias, unused_use, unused_function)]
module social_contracts::my_ip_tests {
    use std::string;
    use std::option;
    
    use mys::test_scenario;
    use mys::test_utils::assert_eq;
    use mys::transfer;
    use mys::object;
    use mys::tx_context;
    
    use social_contracts::my_ip::{Self, MyIP, MyIPRegistry, LicenseAdminCap};
    use social_contracts::profile::{Self, Profile, UsernameRegistry};
    
    // Test addresses
    const CREATOR: address = @0xA1;
    const USER: address = @0xB2;
    
    #[test]
    fun test_create_license() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Set up registry and profile
        init_test_environment(&mut scenario);
        
        // Create license with CC-BY
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let mut registry = test_scenario::take_shared<MyIPRegistry>(&scenario);
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            my_ip::create_license(
                &mut registry,
                &profile,
                string::utf8(b"Test IP"),
                string::utf8(b"Test description"),
                0, // Creative Commons
                my_ip::cc_by_license_flags(),
                option::none(), // proof_of_creativity_id
                option::none(), // custom_license_uri_bytes
                option::none(), // revenue_recipient
                true, // transferable
                option::none(), // expires_at
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Verify license was created and has correct properties
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let license = test_scenario::take_from_sender<MyIP>(&scenario);
            let admin_cap = test_scenario::take_from_sender<LicenseAdminCap>(&scenario);
            
            assert_eq(my_ip::name(&license), string::utf8(b"Test IP"));
            assert_eq(my_ip::description(&license), string::utf8(b"Test description"));
            assert_eq(my_ip::creator(&license), CREATOR);
            assert_eq(my_ip::license_type(&license), 0);
            assert_eq(my_ip::permission_flags(&license), my_ip::cc_by_license_flags());
            assert_eq(my_ip::license_state(&license), 0); // Active
            assert_eq(my_ip::is_transferable(&license), true);
            
            // Verify validation functions
            assert_eq(my_ip::is_commercial_use_allowed(&license), true);
            assert_eq(my_ip::is_derivatives_allowed(&license), true);
            assert_eq(my_ip::is_public_license(&license), true);
            assert_eq(my_ip::is_attribution_required(&license), true);
            assert_eq(my_ip::is_share_alike_required(&license), false);
            assert_eq(my_ip::is_authority_required(&license), false);
            assert_eq(my_ip::is_revenue_redirected(&license), false);
            
            test_scenario::return_to_sender(&scenario, license);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_update_license() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup test environment with registry, profile and license
        init_test_environment(&mut scenario);
        create_test_license(&mut scenario);
        
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let mut registry = test_scenario::take_shared<MyIPRegistry>(&scenario);
            let mut license = test_scenario::take_from_sender<MyIP>(&scenario);
            let admin_cap = test_scenario::take_from_sender<LicenseAdminCap>(&scenario);
            
            // Update to CC-BY-SA
            my_ip::update_license_permissions(
                &mut registry,
                &mut license,
                &admin_cap,
                my_ip::cc_by_sa_license_flags(),
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify update
            assert_eq(my_ip::permission_flags(&license), my_ip::cc_by_sa_license_flags());
            assert_eq(my_ip::is_share_alike_required(&license), true);
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, license);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_license_state_change() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup test environment with registry, profile and license
        init_test_environment(&mut scenario);
        create_test_license(&mut scenario);
        
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let mut registry = test_scenario::take_shared<MyIPRegistry>(&scenario);
            let mut license = test_scenario::take_from_sender<MyIP>(&scenario);
            let admin_cap = test_scenario::take_from_sender<LicenseAdminCap>(&scenario);
            
            // Set license to expired
            my_ip::set_license_state(
                &mut registry,
                &mut license,
                &admin_cap,
                1, // Expired
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify state change
            assert_eq(my_ip::license_state(&license), 1);
            
            // License validation should fail for expired licenses
            assert_eq(my_ip::is_commercial_use_allowed(&license), false);
            assert_eq(my_ip::is_derivatives_allowed(&license), false);
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, license);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_license_transfer() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup test environment with registry, profile and license
        init_test_environment(&mut scenario);
        create_test_license(&mut scenario);
        
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let registry = test_scenario::take_shared<MyIPRegistry>(&scenario);
            let license = test_scenario::take_from_sender<MyIP>(&scenario);
            let admin_cap = test_scenario::take_from_sender<LicenseAdminCap>(&scenario);
            
            // Transfer license to USER
            transfer::public_transfer(license, USER);
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        
        // Verify USER now has the license
        {
            test_scenario::next_tx(&mut scenario, USER);
            let license = test_scenario::take_from_sender<MyIP>(&scenario);
            
            // Creator is still CREATOR 
            assert_eq(my_ip::creator(&license), CREATOR);
            
            test_scenario::return_to_sender(&scenario, license);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_revenue_recipient() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup test environment with registry, profile and license
        init_test_environment(&mut scenario);
        create_test_license(&mut scenario);
        
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let mut registry = test_scenario::take_shared<MyIPRegistry>(&scenario);
            let mut license = test_scenario::take_from_sender<MyIP>(&scenario);
            let admin_cap = test_scenario::take_from_sender<LicenseAdminCap>(&scenario);
            
            // Set revenue recipient to USER
            my_ip::update_revenue_recipient(
                &mut registry,
                &mut license,
                &admin_cap,
                USER,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify revenue redirection
            assert_eq(my_ip::is_revenue_redirected(&license), true);
            let recipient = my_ip::revenue_recipient(&license);
            
            // Create a local variable to hold the USER address for the comparison
            let user_addr = USER;
            assert_eq(option::contains(recipient, &user_addr), true);
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, license);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_admin_cap_transfer() {
        let mut scenario = test_scenario::begin(CREATOR);
        
        // Setup test environment with registry, profile and license
        init_test_environment(&mut scenario);
        create_test_license(&mut scenario);
        
        {
            test_scenario::next_tx(&mut scenario, CREATOR);
            let admin_cap = test_scenario::take_from_sender<LicenseAdminCap>(&scenario);
            
            // Transfer admin capability to USER
            transfer::public_transfer(admin_cap, USER);
        };
        
        // Verify USER now has admin capability
        {
            test_scenario::next_tx(&mut scenario, USER);
            let admin_cap = test_scenario::take_from_sender<LicenseAdminCap>(&scenario);
            
            // At this point, USER should be able to update the license
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_license_types() {
        let scenario = test_scenario::begin(CREATOR);
        
        // Test different predefined license types
        let cc_by = my_ip::cc_by_license_flags();
        let cc_by_sa = my_ip::cc_by_sa_license_flags();
        let cc_by_nc = my_ip::cc_by_nc_license_flags();
        let cc_by_nd = my_ip::cc_by_nd_license_flags();
        let personal_use = my_ip::personal_use_license_flags();
        let token_bound = my_ip::token_bound_license_flags();
        
        // CC BY allows commercial use and derivatives
        assert_eq(my_ip::is_commercial_use_allowed_for_flags(cc_by), true);
        assert_eq(my_ip::is_derivatives_allowed_for_flags(cc_by), true);
        
        // CC BY-NC does not allow commercial use
        assert_eq(my_ip::is_commercial_use_allowed_for_flags(cc_by_nc), false);
        
        // CC BY-ND does not allow derivatives
        assert_eq(my_ip::is_derivatives_allowed_for_flags(cc_by_nd), false);
        
        // CC BY-SA requires share-alike
        assert_eq(my_ip::is_share_alike_required_for_flags(cc_by_sa), true);
        
        // Personal use does not allow commercial use or derivatives
        assert_eq(my_ip::is_commercial_use_allowed_for_flags(personal_use), false);
        assert_eq(my_ip::is_derivatives_allowed_for_flags(personal_use), false);
        
        // Token bound requires authority
        assert_eq(my_ip::is_authority_required_for_flags(token_bound), true);
        
        test_scenario::end(scenario);
    }
    
    // Helper to initialize registry and create a test profile
    fun init_test_environment(scenario: &mut test_scenario::Scenario) {
        // Initialize registry
        test_scenario::next_tx(scenario, CREATOR);
        {
            my_ip::test_init(test_scenario::ctx(scenario));
            
            // Initialize profile registry
            profile::init_for_testing(test_scenario::ctx(scenario));
        };
        
        // Create profile
        test_scenario::next_tx(scenario, CREATOR);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(scenario);
            
            profile::create_profile(
                &mut registry,
                string::utf8(b"Test User"),
                string::utf8(b"test_user"),
                string::utf8(b"This is a test profile"),
                b"https://example.com/profile.jpg",
                b"",
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(registry);
        };
    }
    
    // Helper to create a test license
    fun create_test_license(scenario: &mut test_scenario::Scenario) {
        test_scenario::next_tx(scenario, CREATOR);
        {
            let mut registry = test_scenario::take_shared<MyIPRegistry>(scenario);
            let profile = test_scenario::take_from_sender<Profile>(scenario);
            
            my_ip::create_license(
                &mut registry,
                &profile,
                string::utf8(b"Test IP"),
                string::utf8(b"Test description"),
                0, // Creative Commons
                my_ip::cc_by_license_flags(),
                option::none(), // proof_of_creativity_id
                option::none(), // custom_license_uri_bytes
                option::none(), // revenue_recipient
                true, // transferable
                option::none(), // expires_at
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(scenario, profile);
        };
    }
    
    // === Flag Helper Functions ===
    // These wrapper functions test flag permissions without directly accessing constants
    
    fun is_commercial_use_allowed_for_flags(flags: u64): bool {
        // Create a MyIP with these flags to test
        let custom_ip = create_test_ip_with_flags(flags);
        let result = my_ip::is_commercial_use_allowed(&custom_ip);
        my_ip::test_destroy(custom_ip);
        result
    }
    
    fun is_derivatives_allowed_for_flags(flags: u64): bool {
        let custom_ip = create_test_ip_with_flags(flags);
        let result = my_ip::is_derivatives_allowed(&custom_ip);
        my_ip::test_destroy(custom_ip);
        result
    }
    
    fun is_public_license_for_flags(flags: u64): bool {
        let custom_ip = create_test_ip_with_flags(flags);
        let result = my_ip::is_public_license(&custom_ip);
        my_ip::test_destroy(custom_ip);
        result
    }
    
    fun is_authority_required_for_flags(flags: u64): bool {
        let custom_ip = create_test_ip_with_flags(flags);
        let result = my_ip::is_authority_required(&custom_ip);
        my_ip::test_destroy(custom_ip);
        result
    }
    
    fun is_share_alike_required_for_flags(flags: u64): bool {
        let custom_ip = create_test_ip_with_flags(flags);
        let result = my_ip::is_share_alike_required(&custom_ip);
        my_ip::test_destroy(custom_ip);
        result
    }
    
    fun is_attribution_required_for_flags(flags: u64): bool {
        let custom_ip = create_test_ip_with_flags(flags);
        let result = my_ip::is_attribution_required(&custom_ip);
        my_ip::test_destroy(custom_ip);
        result
    }
    
    fun is_revenue_redirected_for_flags(flags: u64): bool {
        let custom_ip = create_test_ip_with_flags(flags);
        let result = my_ip::is_revenue_redirected(&custom_ip);
        my_ip::test_destroy(custom_ip);
        result
    }
    
    // Create a test MyIP object with specific flags (not persisted)
    fun create_test_ip_with_flags(permission_flags: u64): MyIP {
        my_ip::create(
            string::utf8(b"Test"),
            string::utf8(b"Test"),
            0, // Creative Commons
            permission_flags,
            option::none(),
            option::none(),
            option::none(),
            true,
            option::none(),
            &mut tx_context::dummy()
        )
    }
} 