// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module mys::my_ip_tests {
    use std::string;
    
    use mys::test_scenario;
    use mys::my_ip::{Self, MyIP};
    use mys::tx_context;
    
    const CREATOR: address = @0x1;
    const OTHER_USER: address = @0x2;
    
    #[test]
    fun test_create_my_ip() {
        let scenario = test_scenario::begin(CREATOR);
        {
            // Create a new IP object
            let name = string::utf8(b"My Creative Work");
            let description = string::utf8(b"This is a description of my creative work");
            
            let ip = my_ip::create(
                name,
                description,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify IP properties
            assert!(my_ip::creator(&ip) == CREATOR, 0);
            assert!(my_ip::name(&ip) == name, 0);
            assert!(my_ip::description(&ip) == description, 0);
            assert!(my_ip::creation_time(&ip) > 0, 0);
            
            // Transfer the IP to the creator
            mys::transfer::transfer(ip, CREATOR);
        };
        
        // Check IP exists in the next transaction
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let ip = test_scenario::take_from_sender<MyIP>(&scenario);
            
            // Verify IP properties again
            assert!(my_ip::creator(&ip) == CREATOR, 0);
            assert!(my_ip::name(&ip) == string::utf8(b"My Creative Work"), 0);
            assert!(my_ip::description(&ip) == string::utf8(b"This is a description of my creative work"), 0);
            
            // Test setting PoC ID
            my_ip::set_poc_id(&mut ip, @0x999);
            
            test_scenario::return_to_sender(&scenario, ip);
        };
        
        test_scenario::end(scenario);
    }
}