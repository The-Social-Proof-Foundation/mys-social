// Copyright (c) The Social Proof Foundation, LLC.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module social_contracts::message_tests {
    use mys::test_scenario::{Self, Scenario};
    use mys::clock::{Self, Clock};
    use social_contracts::message::{Self, Registry, Conversation};

    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    const USER3: address = @0x3;

    // === Test Helpers ===

    fun setup_registry(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        {
            message::init_for_testing(test_scenario::ctx(scenario));
        };
    }

    fun setup_clock(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::share_for_testing(clock);
        };
    }

    // === Registry Tests ===

    #[test]
    fun test_init_registry() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            test_scenario::return_shared(registry);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_pause_unpause() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = test_scenario::take_shared<Registry>(&scenario);
            
            message::pause(&mut registry, true, test_scenario::ctx(&mut scenario));
            message::pause(&mut registry, false, test_scenario::ctx(&mut scenario));
            
            test_scenario::return_shared(registry);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = message::E_NOT_ADMIN)]
    fun test_pause_unauthorized() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<Registry>(&scenario);
            message::pause(&mut registry, true, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        test_scenario::end(scenario);
    }

    // === Conversation Creation Tests ===

    #[test]
    fun test_create_conversation() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            
            message::create_conversation(
                &registry,
                0, // DM
                b"test_meta_hash",
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };

        // Verify conversation exists
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let conv = test_scenario::take_from_sender<Conversation>(&scenario);
            assert!(message::is_member(&conv, USER1), 0);
            assert!(message::next_seq(&conv) == 1, 1);
            test_scenario::return_to_sender(&scenario, conv);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = message::E_PAUSED)]
    fun test_create_conversation_when_paused() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = test_scenario::take_shared<Registry>(&scenario);
            message::pause(&mut registry, true, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            
            message::create_conversation(
                &registry,
                0,
                b"test",
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };

        test_scenario::end(scenario);
    }

    // === Participant Management Tests ===

    #[test]
    fun test_add_participants() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 1, b"group", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            
            let mut participants = vector::empty<address>();
            vector::push_back(&mut participants, USER2);
            vector::push_back(&mut participants, USER3);
            
            message::add_participants(&mut conv, participants, test_scenario::ctx(&mut scenario));
            
            assert!(message::is_member(&conv, USER2), 0);
            assert!(message::is_member(&conv, USER3), 1);
            
            test_scenario::return_to_sender(&scenario, conv);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_remove_participants() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);

        // Create conversation and add participants
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 1, b"group", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let mut participants = vector::empty<address>();
            vector::push_back(&mut participants, USER2);
            message::add_participants(&mut conv, participants, test_scenario::ctx(&mut scenario));
            test_scenario::return_to_sender(&scenario, conv);
        };

        // Remove participant
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let mut participants = vector::empty<address>();
            vector::push_back(&mut participants, USER2);
            message::remove_participants(&mut conv, participants, test_scenario::ctx(&mut scenario));
            
            assert!(!message::is_member(&conv, USER2), 0);
            
            test_scenario::return_to_sender(&scenario, conv);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_leave_conversation() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 1, b"group", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let mut participants = vector::empty<address>();
            vector::push_back(&mut participants, USER2);
            message::add_participants(&mut conv, participants, test_scenario::ctx(&mut scenario));
            test_scenario::return_to_sender(&scenario, conv);
        };

        // USER2 leaves
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let mut conv = test_scenario::take_from_address<Conversation>(&scenario, USER1);
            message::leave_conversation(&mut conv, test_scenario::ctx(&mut scenario));
            assert!(!message::is_member(&conv, USER2), 0);
            test_scenario::return_to_address(USER1, conv);
        };

        test_scenario::end(scenario);
    }

    // === Message Sending Tests ===

    #[test]
    fun test_send_message() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);
        setup_clock(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0, // TEXT
                0, // No parent
                b"message_hash",
                b"media_hash",
                b"key_ref",
                1000, // client_ts
                b"dedupe_1",
                12345, // nonce
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            assert!(message::next_seq(&conv) == 2, 0);
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = message::E_DEDUPE_USED)]
    fun test_send_message_duplicate_dedupe() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);
        setup_clock(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        // Send first message
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0,
                0,
                b"msg1",
                b"",
                b"",
                1000,
                b"dedupe_same",
                1,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        // Try to send with same dedupe key (should fail)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0,
                0,
                b"msg2",
                b"",
                b"",
                1001,
                b"dedupe_same", // Same dedupe key
                2,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = message::E_NONCE_USED)]
    fun test_send_message_duplicate_nonce() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);
        setup_clock(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        // Send first message
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0,
                0,
                b"msg1",
                b"",
                b"",
                1000,
                b"dedupe_1",
                999, // Nonce
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        // Try to send with same nonce (should fail)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0,
                0,
                b"msg2",
                b"",
                b"",
                1001,
                b"dedupe_2",
                999, // Same nonce
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        test_scenario::end(scenario);
    }

    // === Rate Limiting Tests ===

    #[test]
    #[expected_failure(abort_code = message::E_RATE_LIMIT)]
    fun test_rate_limit_per_user() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);
        setup_clock(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        // Set low rate limit (1 message per user per window)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            message::set_rate_limits(&mut conv, 60, 1, 100, test_scenario::ctx(&mut scenario));
            test_scenario::return_to_sender(&scenario, conv);
        };

        // Send first message (should succeed)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0,
                0,
                b"msg1",
                b"",
                b"",
                1000,
                b"dedupe_1",
                1,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        // Send second message (should fail - rate limited)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0,
                0,
                b"msg2",
                b"",
                b"",
                1001,
                b"dedupe_2",
                2,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        test_scenario::end(scenario);
    }

    // === Edit/Tombstone Tests ===

    #[test]
    fun test_edit_message() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);
        setup_clock(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        // Send message
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0,
                0,
                b"original",
                b"",
                b"",
                1000,
                b"dedupe_1",
                1,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        // Edit message
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            
            message::edit_message(
                &mut conv,
                1, // seq
                b"edited",
                b"",
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, conv);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_tombstone_message() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);
        setup_clock(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        // Send message
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0,
                0,
                b"to_delete",
                b"",
                b"",
                1000,
                b"dedupe_1",
                1,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        // Tombstone message
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            
            message::tombstone_message(
                &mut conv,
                1, // seq
                0, // reason
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, conv);
        };

        test_scenario::end(scenario);
    }

    // === Receipts Tests ===

    #[test]
    fun test_delivery_acknowledgment() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            message::ack_delivery(&mut conv, 5, test_scenario::ctx(&mut scenario));
            test_scenario::return_to_sender(&scenario, conv);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_read_acknowledgment() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            message::ack_read(&mut conv, 3, test_scenario::ctx(&mut scenario));
            test_scenario::return_to_sender(&scenario, conv);
        };

        test_scenario::end(scenario);
    }

    // === Reactions & Pins Tests ===

    #[test]
    fun test_react_to_message() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);
        setup_clock(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        // Send a message
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0,
                0,
                b"msg",
                b"",
                b"",
                1000,
                b"dedupe_1",
                1,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        // React to the message
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            
            message::react(
                &mut conv,
                1, // seq
                128515, // Emoji code (😃)
                true, // add
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, conv);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_pin_message() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);
        setup_clock(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        // Send a message
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(
                &registry,
                &mut conv,
                0,
                0,
                b"msg",
                b"",
                b"",
                1000,
                b"dedupe_1",
                1,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        // Pin the message (admin can pin)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            message::pin(&mut conv, 1, test_scenario::ctx(&mut scenario));
            test_scenario::return_to_sender(&scenario, conv);
        };

        // Unpin the message
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            message::unpin(&mut conv, 1, test_scenario::ctx(&mut scenario));
            test_scenario::return_to_sender(&scenario, conv);
        };

        test_scenario::end(scenario);
    }

    // === Export Range Tests ===

    #[test]
    fun test_export_range() {
        let mut scenario = test_scenario::begin(ADMIN);
        setup_registry(&mut scenario);
        setup_clock(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            message::create_conversation(&registry, 0, b"dm", test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(registry);
        };

        // Send 3 messages
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<Registry>(&scenario);
            let mut conv = test_scenario::take_from_sender<Conversation>(&scenario);
            let clock = test_scenario::take_shared<Clock>(&scenario);
            
            message::send_message(&registry, &mut conv, 0, 0, b"msg1", b"", b"", 1000, b"d1", 1, &clock, test_scenario::ctx(&mut scenario));
            message::send_message(&registry, &mut conv, 0, 0, b"msg2", b"", b"", 1001, b"d2", 2, &clock, test_scenario::ctx(&mut scenario));
            message::send_message(&registry, &mut conv, 0, 0, b"msg3", b"", b"", 1002, b"d3", 3, &clock, test_scenario::ctx(&mut scenario));
            
            test_scenario::return_shared(registry);
            test_scenario::return_to_sender(&scenario, conv);
            test_scenario::return_shared(clock);
        };

        // Export range
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let conv = test_scenario::take_from_sender<Conversation>(&scenario);
            
            let messages = message::export_range(&conv, 1, 2);
            assert!(vector::length(&messages) == 2, 0);
            
            test_scenario::return_to_sender(&scenario, conv);
        };

        test_scenario::end(scenario);
    }
}

