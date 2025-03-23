#[test_only]
module mys::table_tests {
    use mys::table::{Self, Table};
    use mys::test_scenario::{Self as ts, Scenario};

    const TEST_SENDER: address = @0xCAFE;

    #[test]
    fun test_table_basic_operations() {
        let scenario = ts::begin(TEST_SENDER);
        test_table_operations(&mut scenario);
        ts::end(scenario);
    }

    fun test_table_operations(test: &mut Scenario) {
        // Test table creation and insertion
        ts::next_tx(test, TEST_SENDER);
        {
            let ctx = ts::ctx(test);
            
            // Create table for key: u64, value: address
            let table = table::new<u64, address>(ctx);
            
            // Check initial state
            assert!(table::is_empty(&table), 0);
            assert!(table::length(&table) == 0, 0);
            
            // Add entries
            table::add(&mut table, 1, @0x1);
            table::add(&mut table, 2, @0x2);
            table::add(&mut table, 3, @0x3);
            
            // Verify entries were added
            assert!(!table::is_empty(&table), 0);
            assert!(table::length(&table) == 3, 0);
            assert!(table::contains(&table, 1), 0);
            assert!(table::contains(&table, 2), 0);
            assert!(table::contains(&table, 3), 0);
            assert!(!table::contains(&table, 4), 0);
            
            // Borrow values
            let addr1 = table::borrow(&table, 1);
            assert!(*addr1 == @0x1, 0);
            
            // Modify a value
            let addr2_mut = table::borrow_mut(&mut table, 2);
            *addr2_mut = @0x22;
            
            // Verify the modification
            assert!(*table::borrow(&table, 2) == @0x22, 0);
            
            // Remove an entry
            let addr3 = table::remove(&mut table, 3);
            assert!(addr3 == @0x3, 0);
            assert!(!table::contains(&table, 3), 0);
            assert!(table::length(&table) == 2, 0);
            
            // Store the table for later use
            ts::return_to_sender(test, table);
        };
        
        // Test table with different operations
        ts::next_tx(test, TEST_SENDER);
        {
            let table = ts::take_from_sender<Table<u64, address>>(test);
            
            // Verify previous state persisted
            assert!(table::length(&table) == 2, 0);
            assert!(table::contains(&table, 1), 0);
            assert!(table::contains(&table, 2), 0);
            assert!(!table::contains(&table, 3), 0);
            
            // Remove remaining entries
            let _addr1 = table::remove(&mut table, 1);
            let _addr2 = table::remove(&mut table, 2);
            
            // Verify table is empty
            assert!(table::is_empty(&table), 0);
            assert!(table::length(&table) == 0, 0);
            
            // Destroy empty table
            table::destroy_empty(table);
        };
    }

    #[test]
    fun test_table_drop() {
        let scenario = ts::begin(TEST_SENDER);
        
        ts::next_tx(&mut scenario, TEST_SENDER);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Create table for key: u64, value: u64 (droppable)
            let table = table::new<u64, u64>(ctx);
            
            // Add entries
            table::add(&mut table, 1, 100);
            table::add(&mut table, 2, 200);
            
            // Use drop to destroy non-empty table
            table::drop(table);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = mys::table::ETableNotEmpty)]
    fun test_destroy_non_empty_table() {
        let scenario = ts::begin(TEST_SENDER);
        
        ts::next_tx(&mut scenario, TEST_SENDER);
        {
            let ctx = ts::ctx(&mut scenario);
            
            let table = table::new<u64, address>(ctx);
            table::add(&mut table, 1, @0x1);
            
            // This should abort because the table is not empty
            table::destroy_empty(table);
        };
        
        ts::end(scenario);
    }
    
    #[test]
    fun test_multiple_tables() {
        let scenario = ts::begin(TEST_SENDER);
        
        ts::next_tx(&mut scenario, TEST_SENDER);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Create two tables with different types
            let table1 = table::new<u64, bool>(ctx);
            let table2 = table::new<address, vector<u8>>(ctx);
            
            // Add entries to first table
            table::add(&mut table1, 1, true);
            table::add(&mut table1, 2, false);
            
            // Add entries to second table
            table::add(&mut table2, @0x1, b"one");
            table::add(&mut table2, @0x2, b"two");
            
            // Verify entries in first table
            assert!(*table::borrow(&table1, 1) == true, 0);
            assert!(*table::borrow(&table1, 2) == false, 0);
            
            // Verify entries in second table
            assert!(*table::borrow(&table2, @0x1) == b"one", 0);
            assert!(*table::borrow(&table2, @0x2) == b"two", 0);
            
            // Clean up
            table::drop(table1);
            
            // Remove entries from second table and destroy it
            let _ = table::remove(&mut table2, @0x1);
            let _ = table::remove(&mut table2, @0x2);
            table::destroy_empty(table2);
        };
        
        ts::end(scenario);
    }
}