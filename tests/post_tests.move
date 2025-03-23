// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module mys::post_tests {
    use std::string;
    use std::option;
    
    use mys::test_scenario::{Self, Scenario};
    use mys::profile::{Self, Profile};
    use mys::post::{Self, Post, Comment, Likes};
    use mys::object;
    use mys::url;
    use mys::coin::{Self, Coin};
    use mys::mys::MYS;
    use mys::tx_context;
    
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    
    // Helper function to create a test profile
    fun create_test_profile(scenario: &mut Scenario, name: vector<u8>): Profile {
        let display_name = string::utf8(name);
        let bio = string::utf8(b"Test bio");
        let profile_picture = option::some(url::new_unsafe_from_bytes(b"https://example.com/profile.jpg"));
        
        profile::create_profile(
            display_name,
            bio,
            profile_picture,
            test_scenario::ctx(scenario)
        )
    }
    
    #[test]
    fun test_create_post() {
        let scenario = test_scenario::begin(USER1);
        
        // Create a profile for USER1
        let user1_profile = create_test_profile(&mut scenario, b"User One");
        mys::transfer::transfer(user1_profile, USER1);
        
        // Create a post
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            let content = string::utf8(b"This is my first post!");
            let media_url = option::some(b"https://example.com/image.jpg");
            let mentions = vector[];
            
            let post = post::create_post(
                &profile,
                content,
                media_url,
                mentions,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify post properties
            assert!(post::author(&post) == object::uid_to_address(profile::id(&profile)), 0);
            assert!(post::content(&post) == content, 0);
            assert!(option::is_some(post::media(&post)), 0);
            assert!(post::like_count(&post) == 0, 0);
            assert!(post::comment_count(&post) == 0, 0);
            
            // Share post
            mys::transfer::share_object(post);
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // Verify the post exists in the next transaction
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let post = test_scenario::take_shared<Post>(&scenario);
            let likes = test_scenario::take_shared<Likes>(&scenario);
            
            assert!(post::content(&post) == string::utf8(b"This is my first post!"), 0);
            assert!(post::like_count(&post) == 0, 0);
            assert!(post::author(&post) == USER1, 0);
            
            test_scenario::return_shared(post);
            test_scenario::return_shared(likes);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_like_post() {
        let scenario = test_scenario::begin(USER1);
        
        // Create profiles for two users
        let user1_profile = create_test_profile(&mut scenario, b"User One");
        mys::transfer::transfer(user1_profile, USER1);
        
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let user2_profile = create_test_profile(&mut scenario, b"User Two");
            mys::transfer::transfer(user2_profile, USER2);
        };
        
        // Create a post
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            let content = string::utf8(b"This is my first post!");
            let media_url = option::none();
            let mentions = vector[];
            
            post::create_and_share_post(
                &profile,
                content,
                b"",
                mentions,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // USER2 likes USER1's post
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_shared<Post>(&scenario);
            let likes = test_scenario::take_shared<Likes>(&scenario);
            
            post::like_post(
                &mut post,
                &mut likes,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify like count and like state
            assert!(post::like_count(&post) == 1, 0);
            assert!(post::has_liked(&likes, object::uid_to_address(profile::id(&profile))), 0);
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(post);
            test_scenario::return_shared(likes);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_create_comment() {
        let scenario = test_scenario::begin(USER1);
        
        // Create profiles for two users
        let user1_profile = create_test_profile(&mut scenario, b"User One");
        mys::transfer::transfer(user1_profile, USER1);
        
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let user2_profile = create_test_profile(&mut scenario, b"User Two");
            mys::transfer::transfer(user2_profile, USER2);
        };
        
        // Create a post
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            let content = string::utf8(b"This is my first post!");
            let media_url = option::none();
            let mentions = vector[];
            
            post::create_and_share_post(
                &profile,
                content,
                b"",
                mentions,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // USER2 comments on USER1's post
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_shared<Post>(&scenario);
            
            post::create_comment(
                &mut post,
                &profile,
                string::utf8(b"Great post!"),
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify comment count
            assert!(post::comment_count(&post) == 1, 0);
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(post);
        };
        
        // Verify comment exists
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let comment = test_scenario::take_shared<Comment>(&scenario);
            let likes = test_scenario::take_shared<Likes>(&scenario);
            
            // Verify comment properties
            assert!(post::comment_content(&comment) == string::utf8(b"Great post!"), 0);
            assert!(post::comment_author(&comment) == USER2, 0);
            assert!(post::comment_like_count(&comment) == 0, 0);
            
            test_scenario::return_shared(comment);
            test_scenario::return_shared(likes);
        };
        
        test_scenario::end(scenario);
    }
    
    #[test]
    fun test_unlike_post() {
        let scenario = test_scenario::begin(USER1);
        
        // Create profiles for two users
        let user1_profile = create_test_profile(&mut scenario, b"User One");
        mys::transfer::transfer(user1_profile, USER1);
        
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let user2_profile = create_test_profile(&mut scenario, b"User Two");
            mys::transfer::transfer(user2_profile, USER2);
        };
        
        // Create a post
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            
            let content = string::utf8(b"This is my first post!");
            let media_url = option::none();
            let mentions = vector[];
            
            post::create_and_share_post(
                &profile,
                content,
                b"",
                mentions,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
        };
        
        // USER2 likes USER1's post
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_shared<Post>(&scenario);
            let likes = test_scenario::take_shared<Likes>(&scenario);
            
            post::like_post(
                &mut post,
                &mut likes,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(post);
            test_scenario::return_shared(likes);
        };
        
        // USER2 unlikes USER1's post
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let profile = test_scenario::take_from_sender<Profile>(&scenario);
            let post = test_scenario::take_shared<Post>(&scenario);
            let likes = test_scenario::take_shared<Likes>(&scenario);
            
            post::unlike_post(
                &mut post,
                &mut likes,
                &profile,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify like count and like state
            assert!(post::like_count(&post) == 0, 0);
            assert!(!post::has_liked(&likes, object::uid_to_address(profile::id(&profile))), 0);
            
            test_scenario::return_to_sender(&scenario, profile);
            test_scenario::return_shared(post);
            test_scenario::return_shared(likes);
        };
        
        test_scenario::end(scenario);
    }
}