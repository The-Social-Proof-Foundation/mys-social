#[test_only]
module mys::balance_tests {
    use mys::balance::{Self, Balance, Supply};
    use mys::test_scenario::{Self as ts};

    // Dummy coin type for testing
    public struct TEST_BALANCE has drop {}

    #[test]
    fun test_balance_basic_operations() {
        // Test creating a zero balance
        let zero_balance = balance::zero<TEST_BALANCE>();
        assert!(balance::value(&zero_balance) == 0, 0);
        
        // Test split and join operations
        let supply = balance::create_supply(TEST_BALANCE {});
        let balance = balance::increase_supply(&mut supply, 100);
        assert!(balance::value(&balance) == 100, 0);
        assert!(balance::supply_value(&supply) == 100, 0);
        
        // Test split
        let split_balance = balance::split(&mut balance, 40);
        assert!(balance::value(&balance) == 60, 0);
        assert!(balance::value(&split_balance) == 40, 0);
        
        // Test join
        let joined_value = balance::join(&mut balance, split_balance);
        assert!(joined_value == 100, 0);
        assert!(balance::value(&balance) == 100, 0);
        
        // Test withdraw all
        let withdrawn = balance::withdraw_all(&mut balance);
        assert!(balance::value(&balance) == 0, 0);
        assert!(balance::value(&withdrawn) == 100, 0);
        
        // Test destroy zero
        balance::destroy_zero(balance);
        
        // Test decrease supply
        let decreased_value = balance::decrease_supply(&mut supply, withdrawn);
        assert!(decreased_value == 100, 0);
        assert!(balance::supply_value(&supply) == 0, 0);
        
        // Cleanup
        let _ = balance::destroy_supply(supply);
        balance::destroy_zero(zero_balance);
    }
    
    #[test]
    fun test_balance_with_scenario() {
        let scenario = ts::begin(@0x1);
        
        // Create supply and balances
        ts::next_tx(&mut scenario, @0x1);
        {
            let supply = balance::create_supply(TEST_BALANCE {});
            let balance1 = balance::increase_supply(&mut supply, 500);
            let balance2 = balance::increase_supply(&mut supply, 300);
            
            // Verify total supply
            assert!(balance::supply_value(&supply) == 800, 0);
            
            // Verify individual balances
            assert!(balance::value(&balance1) == 500, 0);
            assert!(balance::value(&balance2) == 300, 0);
            
            // Try splitting
            let split_from_1 = balance::split(&mut balance1, 200);
            assert!(balance::value(&balance1) == 300, 0);
            assert!(balance::value(&split_from_1) == 200, 0);
            
            // Join some balances
            balance::join(&mut balance2, split_from_1);
            assert!(balance::value(&balance2) == 500, 0);
            
            // Decrease supply with one balance
            let decreased_value = balance::decrease_supply(&mut supply, balance1);
            assert!(decreased_value == 300, 0);
            assert!(balance::supply_value(&supply) == 500, 0);
            
            // Cleanup
            let _ = balance::decrease_supply(&mut supply, balance2);
            let _ = balance::destroy_supply(supply);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = mys::balance::ENotEnough)]
    fun test_split_too_much() {
        let balance = balance::create_for_testing<TEST_BALANCE>(50);
        
        // This should fail - trying to split more than we have
        let _ = balance::split(&mut balance, 100);
        
        // Cleanup (shouldn't reach here)
        let _ = balance::destroy_for_testing(balance);
    }
    
    #[test]
    #[expected_failure(abort_code = mys::balance::ENonZero)]
    fun test_destroy_non_zero() {
        let balance = balance::create_for_testing<TEST_BALANCE>(50);
        
        // This should fail - trying to destroy a non-zero balance
        balance::destroy_zero(balance);
    }
    
    #[test]
    fun test_withdraw_all() {
        let balance = balance::create_for_testing<TEST_BALANCE>(100);
        
        // Withdraw all should empty the balance
        let withdrawn = balance::withdraw_all(&mut balance);
        assert!(balance::value(&balance) == 0, 0);
        assert!(balance::value(&withdrawn) == 100, 0);
        
        // Original balance should now be zero
        balance::destroy_zero(balance);
        
        // Cleanup
        let _ = balance::destroy_for_testing(withdrawn);
    }
    
    #[test]
    fun test_supply_overflow_protection() {
        let supply = balance::create_supply_for_testing<TEST_BALANCE>();
        
        // Create a large balance
        let large_balance = balance::increase_supply(&mut supply, 1000);
        assert!(balance::supply_value(&supply) == 1000, 0);
        
        // Try to decrease more than in the supply (should fail safely)
        let split_balance = balance::split(&mut large_balance, 300);
        let _ = balance::decrease_supply(&mut supply, split_balance);
        assert!(balance::supply_value(&supply) == 700, 0);
        
        // Cleanup
        let _ = balance::decrease_supply(&mut supply, large_balance);
        assert!(balance::supply_value(&supply) == 0, 0);
        let _ = balance::destroy_supply(supply);
    }
    
    #[test]
    fun test_test_only_functions() {
        // Test the testing-only functionality
        let test_balance = balance::create_for_testing<TEST_BALANCE>(250);
        assert!(balance::value(&test_balance) == 250, 0);
        
        let value = balance::destroy_for_testing(test_balance);
        assert!(value == 250, 0);
        
        let test_supply = balance::create_supply_for_testing<TEST_BALANCE>();
        assert!(balance::supply_value(&test_supply) == 0, 0);
        
        let _ = balance::destroy_supply(test_supply);
    }
}