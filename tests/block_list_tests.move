// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

#[test_only]
#[allow(unused_use, duplicate_alias, unused_mut_ref)]
module social_contracts::block_list_tests {
    use std::vector;
    use std::option;
    
    use mys::test_scenario;
    
    use social_contracts::block_list;
    
    // Test constants
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    const USER3: address = @0x3;
    const ADMIN: address = @0xAD;
    
    // Initialize the block list registry for testing
    fun init_block_list_registry(scenario: &mut test_scenario::Scenario) {
        // Use the test-specific initialization function instead of direct init call
        block_list::test_init(test_scenario::ctx(scenario));
    }
    
    /// Test creating a block list
    #[test]
    fun test_create_block_list() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize block list registry
        init_block_list_registry(&mut scenario);
        
        // Create a block list
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::create_block_list_for_sender(&mut registry, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Verify block list was created
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            assert!(block_list::has_block_list(&registry, USER1), 0);
            assert!(block_list::blocked_count(&registry, USER1) == 0, 1);
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test blocking a wallet
    #[test]
    fun test_block_wallet() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize block list registry
        init_block_list_registry(&mut scenario);
        
        // Create block list for USER1
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::create_block_list_for_sender(&mut registry, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Block USER2
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::block_wallet(&mut registry, USER2, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Verify USER2 is blocked
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            assert!(block_list::is_blocked(&registry, USER1, USER2), 0);
            assert!(block_list::blocked_count(&registry, USER1) == 1, 1);
            
            let blocked_wallets = block_list::get_blocked_wallets(&registry, USER1);
            assert!(vector::length(&blocked_wallets) == 1, 2);
            assert!(*vector::borrow(&blocked_wallets, 0) == USER2, 3);
            
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test unblocking a wallet
    #[test]
    fun test_unblock_wallet() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize block list registry
        init_block_list_registry(&mut scenario);
        
        // Create block list for USER1
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::create_block_list_for_sender(&mut registry, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Block USER2
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::block_wallet(&mut registry, USER2, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Unblock USER2
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::unblock_wallet(&mut registry, USER2, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Verify USER2 is no longer blocked
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            assert!(!block_list::is_blocked(&registry, USER1, USER2), 0);
            assert!(block_list::blocked_count(&registry, USER1) == 0, 0);
            
            let blocked_wallets = block_list::get_blocked_wallets(&registry, USER1);
            assert!(vector::length(&blocked_wallets) == 0, 0);
            
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test blocking multiple users
    #[test]
    fun test_block_multiple_users() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize block list registry
        init_block_list_registry(&mut scenario);
        
        // Create block list for USER1
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::create_block_list_for_sender(&mut registry, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Block USER2
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::block_wallet(&mut registry, USER2, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Block USER3
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::block_wallet(&mut registry, USER3, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Verify both users are blocked
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            assert!(block_list::is_blocked(&registry, USER1, USER2), 0);
            assert!(block_list::is_blocked(&registry, USER1, USER3), 1);
            assert!(block_list::blocked_count(&registry, USER1) == 2, 2);
            
            let blocked_wallets = block_list::get_blocked_wallets(&registry, USER1);
            assert!(vector::length(&blocked_wallets) == 2, 3);
            
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test that users cannot block themselves
    #[test]
    #[expected_failure(abort_code = block_list::ECannotBlockSelf, location = social_contracts::block_list)]
    fun test_cannot_block_self() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize block list registry
        init_block_list_registry(&mut scenario);
        
        // Create block list for USER1
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::create_block_list_for_sender(&mut registry, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Try to block self (should fail)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::block_wallet(&mut registry, USER1, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test that users cannot block the same user twice
    #[test]
    #[expected_failure(abort_code = block_list::EAlreadyBlocked, location = social_contracts::block_list)]
    fun test_already_blocked() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize block list registry
        init_block_list_registry(&mut scenario);
        
        // Create block list for USER1
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::create_block_list_for_sender(&mut registry, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Block USER2
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::block_wallet(&mut registry, USER2, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Try to block USER2 again (should fail)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::block_wallet(&mut registry, USER2, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test that users cannot unblock users who aren't blocked
    #[test]
    #[expected_failure(abort_code = block_list::ENotBlocked, location = social_contracts::block_list)]
    fun test_not_blocked() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize block list registry
        init_block_list_registry(&mut scenario);
        
        // Create block list for USER1
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::create_block_list_for_sender(&mut registry, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Try to unblock USER2 who isn't blocked (should fail)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::unblock_wallet(&mut registry, USER2, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test find_block_list_id function
    #[test]
    fun test_find_block_list_id() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize block list registry
        init_block_list_registry(&mut scenario);
        
        // Create block list for USER1
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            block_list::create_block_list_for_sender(&mut registry, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };
        
        // Test find_block_list_id
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<block_list::BlockListRegistry>(&mut scenario);
            
            // Check that USER1 has a block list
            let id_option = block_list::find_block_list_id(&registry, USER1);
            assert!(option::is_some(&id_option), 0);
            
            // Check that USER2 does not have a block list
            let id_option2 = block_list::find_block_list_id(&registry, USER2);
            assert!(option::is_none(&id_option2), 1);
            
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
} 