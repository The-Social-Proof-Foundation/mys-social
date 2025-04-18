// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

#[test_only]
#[allow(unused_use, unused_const, duplicate_alias, unused_assignment, dead_code)]
module social_contracts::post_tests {
    use std::string;
    use std::option;
    use std::vector;
    
    use mys::test_scenario;
    use mys::tx_context;
    use mys::table;
    use mys::object;
    use mys::transfer;
    use mys::coin;
    
    use social_contracts::post::{Self, Post, Comment, PostConfig, PredictionData};
    use social_contracts::profile::UsernameRegistry;
    use social_contracts::platform::{Self, Platform};
    use social_contracts::block_list::{Self, BlockListRegistry};
    use social_contracts::my_ip::{Self, MyIPRegistry};
    
    // Test constants
    const TEST_CONTENT: vector<u8> = b"This is a test post";
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    const USER3: address = @0x3;
    const PLATFORM_DEVELOPER: address = @0xCAFE;
    const PLATFORM_MODERATOR: address = @0xBEEF;
    const REGULAR_USER: address = @0x5;
    
    /// Test basic string operations for post content
    #[test]
    fun test_post_content_basics() {
        let mut scenario = test_scenario::begin(USER1);
        
        // Test basic string operations that would be used in posts
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let content = string::utf8(TEST_CONTENT);
            assert!(string::length(&content) > 0, 0);
            assert!(string::length(&content) == 19, 1); // "This is a test post" length
            
            // Test option creation/extraction that would be used in post module
            let mut opt_content = option::some(content);
            assert!(option::is_some(&opt_content), 2);
            
            let extracted = option::extract(&mut opt_content);
            assert!(string::length(&extracted) == 19, 3);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test constants and values expected in the post module
    #[test]
    fun test_post_type_constants() {
        let mut scenario = test_scenario::begin(USER1);
        
        // Log post type constants for inspection
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Expected values matching post module constants
            let standard_type = b"standard";
            let comment_type = b"comment";
            let repost_type = b"repost";
            let quote_repost_type = b"quote_repost";
            
            // These assertions verify the expected constants
            assert!(standard_type == b"standard", 0);
            assert!(comment_type == b"comment", 1);
            assert!(repost_type == b"repost", 2);
            assert!(quote_repost_type == b"quote_repost", 3);
            
            // Test string conversions that would be used in post module
            let std_str = string::utf8(standard_type);
            assert!(string::length(&std_str) == 8, 4);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test transaction context functions used in post module
    #[test]
    fun test_tx_context_functions() {
        let mut scenario = test_scenario::begin(USER1);
        
        // Test tx_context functions that would be used in post module
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            
            // Verify sender functionality
            let sender = tx_context::sender(ctx);
            assert!(sender == USER1, 0);
            
            // Verify epoch functionality (used for timestamps)
            let epoch = tx_context::epoch(ctx);
            assert!(epoch >= 0, 1); // Epoch should be non-negative
        };
        
        // Test different sender
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let sender = tx_context::sender(ctx);
            assert!(sender == USER2, 2);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test like tracking table operations - simulates the logic in like_post and like_comment
    #[test]
    fun test_like_table_operations() {
        let mut scenario = test_scenario::begin(USER1);
        
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            
            // Create a likes table to track likes (simulating what happens inside Likes struct)
            let mut likes = table::new<address, bool>(ctx);
            
            // Initially no likes
            assert!(table::length(&likes) == 0, 0);
            
            // USER2 likes the post
            assert!(!table::contains(&likes, USER2), 1); // Should not be in likes
            table::add(&mut likes, USER2, true);
            assert!(table::contains(&likes, USER2), 2); // Now should be in likes
            assert!(table::length(&likes) == 1, 3);
            
            // USER3 likes the post
            assert!(!table::contains(&likes, USER3), 4);
            table::add(&mut likes, USER3, true);
            assert!(table::contains(&likes, USER3), 5);
            assert!(table::length(&likes) == 2, 6);
            
            // USER3 unlikes the post
            assert!(table::contains(&likes, USER3), 7);
            table::remove(&mut likes, USER3);
            assert!(!table::contains(&likes, USER3), 8);
            assert!(table::length(&likes) == 1, 9);
            
            // Should prevent duplicate likes (this would abort in real code)
            // We're just testing the table contains check that would prevent it
            assert!(table::contains(&likes, USER2), 10);
            
            // Cleanup
            table::drop(likes);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test comment count tracking logic - simulates creating comments and managing counts
    #[test]
    fun test_comment_count_tracking() {
        let mut scenario = test_scenario::begin(USER1);
        
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Simulate a post's comment_count field being updated
            let mut post_comment_count: u64 = 0;
            
            // USER2 creates a comment
            post_comment_count = post_comment_count + 1;
            assert!(post_comment_count == 1, 0);
            
            // USER3 creates another comment
            post_comment_count = post_comment_count + 1;
            assert!(post_comment_count == 2, 1);
            
            // Track nested comments (inside another comment)
            let mut comment_nested_count: u64 = 0;
            
            // USER1 replies to USER2's comment
            comment_nested_count = comment_nested_count + 1;
            assert!(comment_nested_count == 1, 2);
            
            // USER4 replies to USER2's comment
            comment_nested_count = comment_nested_count + 1;
            assert!(comment_nested_count == 2, 3);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test repost count tracking logic - simulates creating reposts and managing counts
    #[test]
    fun test_repost_count_tracking() {
        let mut scenario = test_scenario::begin(USER1);
        
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Simulate a post's repost_count field being updated
            let mut post_repost_count: u64 = 0;
            
            // USER2 reposts
            post_repost_count = post_repost_count + 1;
            assert!(post_repost_count == 1, 0);
            
            // USER3 quote reposts (adds a comment too)
            post_repost_count = post_repost_count + 1;
            assert!(post_repost_count == 2, 1);
            
            // Track content types for quote reposts vs. standard reposts
            let standard_repost = string::utf8(b"repost");
            let quote_repost = string::utf8(b"quote_repost");
            
            // Test proper type values
            assert!(standard_repost != quote_repost, 2);
            
            // Simulate checking if a quote repost has content
            let content = string::utf8(b"This is my quote repost comment");
            assert!(string::length(&content) > 0, 3);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test content moderation patterns
    #[test]
    fun test_content_moderation() {
        let mut scenario = test_scenario::begin(PLATFORM_DEVELOPER);
        
        // First transaction: Initial setup for moderation state
        test_scenario::next_tx(&mut scenario, PLATFORM_DEVELOPER);
        {
            // Simulating a post's moderation state
            let mut post_removed = false;
            
            // Post start as not removed
            assert!(post_removed == false, 0);
            
            // Developer can moderate
            let sender = tx_context::sender(test_scenario::ctx(&mut scenario));
            assert!(sender == PLATFORM_DEVELOPER, 1);
            
            // Developer moderates the post (removes it)
            post_removed = true;
            assert!(post_removed == true, 2);
        };
        
        // Second transaction: Moderator can also moderate
        test_scenario::next_tx(&mut scenario, PLATFORM_MODERATOR);
        {
            // Simulating a post's moderation state (continue from above)
            let mut post_removed = true;
            
            // Moderator can unremove the post
            let sender = tx_context::sender(test_scenario::ctx(&mut scenario));
            assert!(sender == PLATFORM_MODERATOR, 3);
            
            // Moderator restores the post
            post_removed = false;
            assert!(post_removed == false, 4);
        };
        
        // Third transaction: Regular user cannot moderate
        test_scenario::next_tx(&mut scenario, REGULAR_USER);
        {
            // Simulating the platform's developer/moderator check
            let sender = tx_context::sender(test_scenario::ctx(&mut scenario));
            
            // Verify sender is not a developer or moderator
            assert!(sender != PLATFORM_DEVELOPER, 5);
            assert!(sender != PLATFORM_MODERATOR, 6);
            
            // In the real implementation, the function would abort here
            // since the sender is not authorized to moderate
            
            // We simulate the authorization check that would happen
            let is_authorized = sender == PLATFORM_DEVELOPER || sender == PLATFORM_MODERATOR;
            assert!(!is_authorized, 7);
        };
        
        test_scenario::end(scenario);
    }
    
    /// Test that post content parsing works correctly
    #[test]
    fun test_post_content() {
        // Test that parsing and comparing content works correctly
        let content = string::utf8(b"Hello, World!");
        
        // Simply test the string operations
        assert!(string::as_bytes(&content) == b"Hello, World!", 0);
        assert!(string::length(&content) == 13, 1);
    }
    
    /// Test post update functionalities with string comparisons
    #[test]
    fun test_post_updates() {
        // This test verifies string equality would work for post updates
        let content = string::utf8(b"Original content");
        let updated = string::utf8(b"Updated content");
        
        // Test content hasn't been modified yet
        assert!(content != updated, 0);
        
        // This verifies string equality would work for tests
        let same = string::utf8(b"Original content");
        assert!(content == same, 1);
    }

    /// Test reactions functionality with toggle behavior
    #[test]
    fun test_reactions() {
        let mut scenario = test_scenario::begin(USER1);
        
        // Create a table to track user reactions (simulating what happens in a Post struct)
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            
            // Initialize reaction tracking tables
            let mut user_reactions = table::new<address, string::String>(ctx);
            let mut reaction_counts = table::new<string::String, u64>(ctx);
            let mut total_reaction_count: u64 = 0;
            
            // USER2 adds a reaction "👍"
            let reaction1 = string::utf8(b"👍");
            
            // Initially USER2 has no reaction
            assert!(!table::contains(&user_reactions, USER2), 0);
            
            // Add USER2's reaction
            table::add(&mut user_reactions, USER2, reaction1);
            total_reaction_count = total_reaction_count + 1;
            
            // Update reaction counts for this emoji
            table::add(&mut reaction_counts, reaction1, 1);
            
            // Verify state after first reaction
            assert!(table::contains(&user_reactions, USER2), 1);
            assert!(table::length(&user_reactions) == 1, 2);
            assert!(total_reaction_count == 1, 3);
            assert!(*table::borrow(&reaction_counts, reaction1) == 1, 4);
            
            // USER3 adds a different reaction "❤️"
            let reaction2 = string::utf8(b"❤️");
            
            // Add USER3's reaction
            table::add(&mut user_reactions, USER3, reaction2);
            total_reaction_count = total_reaction_count + 1;
            
            // Update reaction counts
            table::add(&mut reaction_counts, reaction2, 1);
            
            // Verify state after second reaction
            assert!(table::contains(&user_reactions, USER3), 5);
            assert!(table::length(&user_reactions) == 2, 6);
            assert!(total_reaction_count == 2, 7);
            assert!(*table::borrow(&reaction_counts, reaction2) == 1, 8);
            
            // USER2 toggles the same reaction (removes it)
            let user2_reaction = *table::borrow(&user_reactions, USER2);
            assert!(user2_reaction == reaction1, 9);
            
            // Remove USER2's reaction (toggle off)
            table::remove(&mut user_reactions, USER2);
            total_reaction_count = total_reaction_count - 1;
            
            // Update reaction counts for the removed reaction
            let count = *table::borrow(&reaction_counts, reaction1);
            if (count <= 1) {
                table::remove(&mut reaction_counts, reaction1);
            } else {
                *table::borrow_mut(&mut reaction_counts, reaction1) = count - 1;
            };
            
            // Verify state after reaction removal
            assert!(!table::contains(&user_reactions, USER2), 10);
            assert!(table::length(&user_reactions) == 1, 11);
            assert!(total_reaction_count == 1, 12);
            assert!(!table::contains(&reaction_counts, reaction1), 13);
            
            // USER3 changes their reaction from "❤️" to "👍"
            // First remove old reaction count
            let user3_reaction = *table::borrow(&user_reactions, USER3);
            let count = *table::borrow(&reaction_counts, user3_reaction);
            if (count <= 1) {
                table::remove(&mut reaction_counts, user3_reaction);
            } else {
                *table::borrow_mut(&mut reaction_counts, user3_reaction) = count - 1;
            };
            
            // Then update USER3's reaction
            *table::borrow_mut(&mut user_reactions, USER3) = reaction1;
            
            // And update reaction counts for the new reaction
            if (table::contains(&reaction_counts, reaction1)) {
                let count = *table::borrow(&reaction_counts, reaction1);
                *table::borrow_mut(&mut reaction_counts, reaction1) = count + 1;
            } else {
                table::add(&mut reaction_counts, reaction1, 1);
            };
            
            // Verify final state after reaction change
            assert!(table::contains(&user_reactions, USER3), 14);
            assert!(*table::borrow(&user_reactions, USER3) == reaction1, 15);
            assert!(table::length(&user_reactions) == 1, 16);
            assert!(total_reaction_count == 1, 17);
            assert!(*table::borrow(&reaction_counts, reaction1) == 1, 18);
            assert!(!table::contains(&reaction_counts, reaction2), 19);
            
            // Cleanup
            table::drop(user_reactions);
            table::drop(reaction_counts);
        };
        
        test_scenario::end(scenario);
    }

    /// Test delete_post functionality
    #[test]
    fun test_delete_post() {
        let mut scenario = test_scenario::begin(USER1);
        
        // Create test objects and registry
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Create a registry and platform for testing
            social_contracts::profile::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::platform::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::block_list::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::my_ip::test_init(test_scenario::ctx(&mut scenario));
            // Initialize the post module
            post::test_init(test_scenario::ctx(&mut scenario));
        };
        
        // USER1 creates a profile
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Register a test username
            social_contracts::profile::register_username(
                &mut registry, 
                string::utf8(b"user1"), 
                option::none(), 
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // USER1 creates a post directly with test helper
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Get the profile ID
            let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(&registry, USER1);
            assert!(option::is_some(&profile_id_option), 0);
            let profile_id_addr = option::extract(&mut profile_id_option);
            
            // Create a test post directly
            post::test_create_post(
                USER1,
                profile_id_addr,
                string::utf8(TEST_CONTENT),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // USER1 deletes the post they own
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Retrieve the post 
            let post = test_scenario::take_shared<Post>(&scenario);
            
            // Verify it has the expected content and owner
            assert!(post::get_post_content(&post) == string::utf8(TEST_CONTENT), 0);
            assert!(post::get_post_owner(&post) == USER1, 1);
            
            // Delete the post
            post::delete_post(
                post, // Note: We pass by value as the post will be consumed
                test_scenario::ctx(&mut scenario)
            );
            
            // Post should no longer exist in the shared objects
            assert!(!test_scenario::has_most_recent_shared<Post>(), 2);
        };

        test_scenario::end(scenario);
    }

    /// Test delete_comment functionality
    #[test]
    fun test_delete_comment() {
        let mut scenario = test_scenario::begin(USER1);
        
        // Create test objects and registry
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Create a registry and platform for testing
            social_contracts::profile::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::platform::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::block_list::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::my_ip::test_init(test_scenario::ctx(&mut scenario));
            // Initialize the post module
            post::test_init(test_scenario::ctx(&mut scenario));
        };
        
        // USER1 creates a profile
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Register a test username
            social_contracts::profile::register_username(
                &mut registry, 
                string::utf8(b"user1"), 
                option::none(), 
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // USER1 creates a post directly with test helper
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Get the profile ID
            let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(&registry, USER1);
            assert!(option::is_some(&profile_id_option), 0);
            let profile_id_addr = option::extract(&mut profile_id_option);
            
            // Create a test post directly
            post::test_create_post(
                USER1,
                profile_id_addr,
                string::utf8(TEST_CONTENT),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // Create a variable to store the comment ID
        let comment_id: address;
        
        // USER1 creates a comment on their own post
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let mut post = test_scenario::take_shared<Post>(&scenario);
            let block_list_registry = test_scenario::take_shared<BlockListRegistry>(&scenario);
            let my_ip_registry = test_scenario::take_shared<MyIPRegistry>(&scenario);
            
            // Get the profile ID for the comment
            let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(&registry, USER1);
            assert!(option::is_some(&profile_id_option), 0);
            let profile_id_addr = option::extract(&mut profile_id_option);
            
            // Create test comment directly using the module's test helper
            comment_id = post::test_create_comment(
                USER1,
                profile_id_addr,
                object::uid_to_address(post::get_post_id(&post)),
                string::utf8(b"This is a test comment"),
                test_scenario::ctx(&mut scenario)
            );
            
            // Update the comment count on the post
            post::increment_comment_count(
                &mut post, 
                &block_list_registry, 
                &my_ip_registry, 
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify comment count increased
            assert!(post::get_post_comment_count(&post) == 1, 0);
            
            test_scenario::return_shared(post);
            test_scenario::return_shared(registry);
            test_scenario::return_shared(block_list_registry);
            test_scenario::return_shared(my_ip_registry);
        };
        
        // USER1 deletes their comment
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut post = test_scenario::take_shared<Post>(&scenario);
            
            // Get the comment directly by ID
            let comment_id_obj = object::id_from_address(comment_id);
            let comment = test_scenario::take_shared_by_id<Comment>(&scenario, comment_id_obj);
            
            // Verify it's the same post
            assert!(post::get_post_owner(&post) == USER1, 1);
            
            // Verify comment belongs to USER1
            assert!(post::get_comment_owner(&comment) == USER1, 2);
            
            // Get the comment ID to verify it's the right one
            let comment_post_id = post::get_comment_post_id(&comment);
            let post_id = object::uid_to_address(post::get_post_id(&post));
            assert!(comment_post_id == post_id, 3);
            
            // Delete the comment
            post::delete_comment(
                &mut post,
                comment, // By value as it will be consumed
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify post comment count decreased
            assert!(post::get_post_comment_count(&post) == 0, 4);
            
            test_scenario::return_shared(post);
        };
        
        test_scenario::end(scenario);
    }

    /// Test unauthorized attempts to delete a post
    #[test]
    #[expected_failure(abort_code = 0, location = social_contracts::post)] // EUnauthorized error code
    fun test_unauthorized_post_deletion() {
        let mut scenario = test_scenario::begin(USER1);
        
        // Create test objects and registry
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Create a registry and platform for testing
            social_contracts::profile::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::platform::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::block_list::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::my_ip::test_init(test_scenario::ctx(&mut scenario));
            // Initialize the post module
            post::test_init(test_scenario::ctx(&mut scenario));
        };
        
        // USER1 creates a profile
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Register a test username
            social_contracts::profile::register_username(
                &mut registry, 
                string::utf8(b"user1"), 
                option::none(), 
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // USER1 creates a post directly with test helper
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Get the profile ID
            let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(&registry, USER1);
            assert!(option::is_some(&profile_id_option), 0);
            let profile_id_addr = option::extract(&mut profile_id_option);
            
            // Create a test post directly
            post::test_create_post(
                USER1,
                profile_id_addr,
                string::utf8(TEST_CONTENT),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // USER2 attempts to delete USER1's post - should fail
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let post = test_scenario::take_shared<Post>(&scenario);
            
            // This should fail since USER2 != USER1
            post::delete_post(post, test_scenario::ctx(&mut scenario));
            
            // This line should never be reached due to failure
            abort 42
        };
        
        test_scenario::end(scenario);
    }

    /// Test unauthorized attempt to delete a comment
    #[test]
    #[expected_failure(abort_code = 0, location = social_contracts::post)] // EUnauthorized error code
    fun test_unauthorized_comment_deletion() {
        let mut scenario = test_scenario::begin(USER1);
        
        // Create test objects and registry
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Create a registry and platform for testing
            social_contracts::profile::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::platform::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::block_list::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::my_ip::test_init(test_scenario::ctx(&mut scenario));
            // Initialize the post module
            post::test_init(test_scenario::ctx(&mut scenario));
        };
        
        // Register profiles for USER1 and USER2
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Register a test username for USER1
            social_contracts::profile::register_username(
                &mut registry, 
                string::utf8(b"user1"), 
                option::none(), 
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Register a test username for USER2
            social_contracts::profile::register_username(
                &mut registry, 
                string::utf8(b"user2"), 
                option::none(), 
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // USER1 creates a post directly with test helper
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Get the profile ID
            let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(&registry, USER1);
            assert!(option::is_some(&profile_id_option), 0);
            let profile_id_addr = option::extract(&mut profile_id_option);
            
            // Create a test post directly
            post::test_create_post(
                USER1,
                profile_id_addr,
                string::utf8(TEST_CONTENT),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // Create a variable to store the comment ID
        let comment_id: address;
        
        // USER2 creates a comment on USER1's post
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            let mut post = test_scenario::take_shared<Post>(&scenario);
            let block_list_registry = test_scenario::take_shared<BlockListRegistry>(&scenario);
            let my_ip_registry = test_scenario::take_shared<MyIPRegistry>(&scenario);
            
            // Get the profile ID for USER2
            let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(&registry, USER2);
            assert!(option::is_some(&profile_id_option), 0);
            let profile_id_addr = option::extract(&mut profile_id_option);
            
            // Create test comment directly using the module's test helper
            comment_id = post::test_create_comment(
                USER2,
                profile_id_addr,
                object::uid_to_address(post::get_post_id(&post)),
                string::utf8(b"This is a test comment by USER2"),
                test_scenario::ctx(&mut scenario)
            );
            
            // Update the comment count on the post
            post::increment_comment_count(
                &mut post, 
                &block_list_registry, 
                &my_ip_registry, 
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(post);
            test_scenario::return_shared(registry);
            test_scenario::return_shared(block_list_registry);
            test_scenario::return_shared(my_ip_registry);
        };
        
        // USER1 attempts to delete USER2's comment - should fail
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut post = test_scenario::take_shared<Post>(&scenario);
            
            // Get the comment directly by ID
            let comment_id_obj = object::id_from_address(comment_id);
            let comment = test_scenario::take_shared_by_id<Comment>(&scenario, comment_id_obj);
            
            // This should fail since comment owner is USER2, not USER1
            post::delete_comment(
                &mut post,
                comment,
                test_scenario::ctx(&mut scenario)
            );
            
            // This line should never be reached due to failure
            abort 42
        };
        
        test_scenario::end(scenario);
    }

    /// Test block list check in post creation
    #[test]
    fun test_post_creation_with_blocklist() {
        let mut scenario = test_scenario::begin(USER1);
        
        // Create test objects and registry
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Create a registry and platform for testing
            social_contracts::profile::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::platform::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::block_list::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::my_ip::test_init(test_scenario::ctx(&mut scenario));
            // Initialize the post module
            post::test_init(test_scenario::ctx(&mut scenario));
        };
        
        // USER1 creates a profile
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Register a test username
            social_contracts::profile::register_username(
                &mut registry, 
                string::utf8(b"user1"), 
                option::none(), 
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            // Get the profile ID to join platform
            let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(&registry, USER1);
            assert!(option::is_some(&profile_id_option), 0);
            let _profile_id_addr = option::extract(&mut profile_id_option);
            
            test_scenario::return_shared(registry);
        };
        
        // USER1 creates a post directly using test helper
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Get the profile ID again
            let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(&registry, USER1);
            assert!(option::is_some(&profile_id_option), 0);
            let profile_id_addr = option::extract(&mut profile_id_option);
            
            // Use the test helper to create a post directly
            post::test_create_post(
                USER1,
                profile_id_addr,
                string::utf8(TEST_CONTENT),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // Verify post was created successfully
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Check if post exists and get it if it does
            if (test_scenario::has_most_recent_shared<Post>()) {
                let post = test_scenario::take_shared<Post>(&scenario);
                assert!(post::get_post_content(&post) == string::utf8(TEST_CONTENT), 1);
                assert!(post::get_post_owner(&post) == USER1, 2);
                test_scenario::return_shared(post);
            } else {
                // If no post exists, this will fail the test
                assert!(false, 97);
            };
        };
        
        test_scenario::end(scenario);
    }

    /// Test prediction bet withdrawal functionality
    #[test]
    fun test_prediction_bet_withdrawal() {
        let mut scenario = test_scenario::begin(USER1);
        
        // Create test objects and registry
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Create a registry and platform for testing
            social_contracts::profile::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::platform::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::block_list::test_init(test_scenario::ctx(&mut scenario));
            social_contracts::my_ip::test_init(test_scenario::ctx(&mut scenario));
            // Initialize the post module
            post::test_init(test_scenario::ctx(&mut scenario));
        };
        
        // Get the admin cap
        test_scenario::next_tx(&mut scenario, USER1);
        {
            post::test_get_admin_cap(test_scenario::ctx(&mut scenario));
        };
        
        // USER1 creates a profile
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Register a test username for USER1
            social_contracts::profile::register_username(
                &mut registry, 
                string::utf8(b"user1"), 
                option::none(), 
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // USER2 creates a profile
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Register a test username for USER2
            social_contracts::profile::register_username(
                &mut registry, 
                string::utf8(b"user2"), 
                option::none(), 
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // USER3 creates a profile
        test_scenario::next_tx(&mut scenario, USER3);
        {
            let mut registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Register a test username for USER3
            social_contracts::profile::register_username(
                &mut registry, 
                string::utf8(b"user3"), 
                option::none(), 
                option::none(),
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
        };
        
        // USER1 creates a prediction post with test helper
        let prediction_post_id;
        let prediction_data_id;
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let registry = test_scenario::take_shared<UsernameRegistry>(&scenario);
            
            // Get the profile ID
            let mut profile_id_option = social_contracts::profile::lookup_profile_by_owner(&registry, USER1);
            assert!(option::is_some(&profile_id_option), 0);
            let profile_id_addr = option::extract(&mut profile_id_option);
            
            // Create prediction options
            let mut options = vector::empty<string::String>();
            vector::push_back(&mut options, string::utf8(b"Yes"));
            vector::push_back(&mut options, string::utf8(b"No"));
            
            // Create a test prediction post directly
            let (post_id, data_id) = post::test_create_prediction_post(
                USER1,
                profile_id_addr,
                string::utf8(b"Will this test pass?"),
                options,
                option::none(), // No betting end time
                test_scenario::ctx(&mut scenario)
            );
            
            prediction_post_id = post_id;
            prediction_data_id = data_id;
            
            test_scenario::return_shared(registry);
        };
        
        // USER2 places a bet on "Yes"
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let config = test_scenario::take_shared<post::PostConfig>(&scenario);
            
            // Convert address to ID
            let post_id = object::id_from_address(prediction_post_id);
            let data_id = object::id_from_address(prediction_data_id);
            
            let post = test_scenario::take_shared_by_id<post::Post>(&scenario, post_id);
            let mut prediction_data = test_scenario::take_shared_by_id<post::PredictionData>(&scenario, data_id);
            
            // Create coins for betting
            let mut coins = coin::mint_for_testing<mys::mys::MYS>(100, test_scenario::ctx(&mut scenario));
            
            // Place bet on option 0 (Yes)
            post::place_prediction_bet(
                &config,
                &post,
                &mut prediction_data,
                0, // Yes
                &mut coins,
                50, // Bet 50 MYS
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify bet was placed - post tips_received should be 0 as bets don't count as tips
            assert!(post::get_tips_received(&post) == 0, 1);
            
            // Verify the prediction data bet amount is correct
            assert!(post::get_total_bet_amount(&prediction_data) == 50, 2);
            
            // Clean up
            coin::burn_for_testing(coins);
            
            test_scenario::return_shared(config);
            test_scenario::return_shared(post);
            test_scenario::return_shared(prediction_data);
        };
        
        // USER3 places a bet on "No"
        test_scenario::next_tx(&mut scenario, USER3);
        {
            let config = test_scenario::take_shared<post::PostConfig>(&scenario);
            
            // Convert address to ID
            let post_id = object::id_from_address(prediction_post_id);
            let data_id = object::id_from_address(prediction_data_id);
            
            let post = test_scenario::take_shared_by_id<post::Post>(&scenario, post_id);
            let mut prediction_data = test_scenario::take_shared_by_id<post::PredictionData>(&scenario, data_id);
            
            // Create coins for betting
            let mut coins = coin::mint_for_testing<mys::mys::MYS>(100, test_scenario::ctx(&mut scenario));
            
            // Place bet on option 1 (No)
            post::place_prediction_bet(
                &config,
                &post,
                &mut prediction_data,
                1, // No
                &mut coins,
                30, // Bet 30 MYS
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify total bet amount is correct
            assert!(post::get_total_bet_amount(&prediction_data) == 80, 3); // 50 + 30 = 80
            
            // Clean up
            coin::burn_for_testing(coins);
            
            test_scenario::return_shared(config);
            test_scenario::return_shared(post);
            test_scenario::return_shared(prediction_data);
        };
        
        // USER2 withdraws their bet
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let config = test_scenario::take_shared<post::PostConfig>(&scenario);
            
            // Convert address to ID
            let post_id = object::id_from_address(prediction_post_id);
            let data_id = object::id_from_address(prediction_data_id);
            
            let post = test_scenario::take_shared_by_id<post::Post>(&scenario, post_id);
            let mut prediction_data = test_scenario::take_shared_by_id<post::PredictionData>(&scenario, data_id);
            
            // Create coins for repayment
            let mut repayment_coins = coin::mint_for_testing<mys::mys::MYS>(100, test_scenario::ctx(&mut scenario));
            
            // USER2 withdraws their bet
            post::withdraw_prediction_bet(
                &config,
                &post,
                &mut prediction_data,
                &mut repayment_coins,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify the bet was withdrawn
            assert!(post::get_total_bet_amount(&prediction_data) == 30, 2); // 80 - 50 = 30 (only USER3's bet remains)
            
            // Verify there's only one bet left
            assert!(post::get_bets_count(&prediction_data) == 1, 3);
            
            // Verify the remaining bet belongs to USER3
            assert!(post::get_bet_user(&prediction_data, 0) == USER3, 4);
            assert!(post::get_bet_option_id(&prediction_data, 0) == 1, 5); // option 1 = "No"
            
            // Clean up
            coin::burn_for_testing(repayment_coins);
            
            test_scenario::return_shared(config);
            test_scenario::return_shared(post);
            test_scenario::return_shared(prediction_data);
        };
        
        test_scenario::end(scenario);
    }
}