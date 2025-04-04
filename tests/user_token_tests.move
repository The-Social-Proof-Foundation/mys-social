// Copyright (c) The Social Proof Foundation LLC
// SPDX-License-Identifier: Apache-2.0

#[test_only]
#[allow(unused_const)]
module mys::user_token_tests {
    use std::ascii;
    use std::string::{Self, String};
    use std::vector;
    
    use mys::test_scenario::{Self, Scenario};
    use mys::user_token::{Self, TokenRegistry, AdminCap, UserTokenOwnership, FeeCollector};
    use mys::coin::{Self, TreasuryCap, CoinMetadata, Coin};
    use mys::tx_context;
    use mys::transfer;
    
    // Test addresses
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    
    // Test token parameters
    const TOKEN_DECIMALS: u8 = 8;
    const TOKEN_SYMBOL: vector<u8> = b"USER1";
    const TOKEN_NAME: vector<u8> = b"User One Token";
    const TOKEN_DESCRIPTION: vector<u8> = b"A test token for User One";
    const TOKEN_ICON_URL: vector<u8> = b"https://example.com/icon.png";
    const TOKEN_COMMISSION: u64 = 500; // 5% in basis points
    const TOKEN_CREATOR_SPLIT: u64 = 8000; // 80% in basis points
    
    // For testing custom token type
    public struct TEST_TOKEN has drop {}
    
    // Test creating a user token
    #[test]
    fun test_create_user_token() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Module initialization happens automatically
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Verify the admin cap was transferred to ADMIN
            assert!(test_scenario::has_most_recent_for_address<AdminCap>(ADMIN), 0);
            
            // Verify the token registry was shared
            assert!(test_scenario::has_most_recent_shared<TokenRegistry>(), 0);
        };
        
        // Create a user token
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let registry = test_scenario::take_shared<TokenRegistry>(&scenario);
            
            user_token::create_user_token<TEST_TOKEN>(
                &admin_cap,
                &mut registry,
                USER1,
                TEST_TOKEN {},
                TOKEN_DECIMALS,
                TOKEN_SYMBOL,
                TOKEN_NAME,
                TOKEN_DESCRIPTION,
                true,
                TOKEN_ICON_URL,
                true,
                TOKEN_COMMISSION,
                true,
                TOKEN_CREATOR_SPLIT,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(registry);
        };
        
        // Verify the token was created
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // User should have a token ownership object
            assert!(test_scenario::has_most_recent_for_address<UserTokenOwnership<TEST_TOKEN>>(USER1), 0);
            
            // Verify token metadata was shared
            assert!(test_scenario::has_most_recent_shared<CoinMetadata<TEST_TOKEN>>(), 0);
            
            // Verify treasury cap was transferred to admin
            assert!(test_scenario::has_most_recent_for_address<TreasuryCap<TEST_TOKEN>>(ADMIN), 0);
            
            // Verify fee collector was shared
            assert!(test_scenario::has_most_recent_shared<FeeCollector<TEST_TOKEN>>(), 0);
            
            // Check token info in registry
            let registry = test_scenario::take_shared<TokenRegistry>(&scenario);
            let (has_token, token_info) = user_token::get_user_token_info(&registry, USER1);
            
            assert!(has_token, 0);
            assert!(user_token::user(&token_info) == USER1, 0);
            assert!(user_token::commission_bps(&token_info) == TOKEN_COMMISSION, 0);
            assert!(user_token::creator_split_bps(&token_info) == TOKEN_CREATOR_SPLIT, 0);
            assert!(user_token::platform_split_bps(&token_info) == 10000 - TOKEN_CREATOR_SPLIT, 0);
            
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test minting tokens
    #[test]
    fun test_mint_tokens() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create a user token first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let registry = test_scenario::take_shared<TokenRegistry>(&scenario);
            
            user_token::create_user_token<TEST_TOKEN>(
                &admin_cap,
                &mut registry,
                USER1,
                TEST_TOKEN {},
                TOKEN_DECIMALS,
                TOKEN_SYMBOL,
                TOKEN_NAME,
                TOKEN_DESCRIPTION,
                true,
                TOKEN_ICON_URL,
                true,
                TOKEN_COMMISSION,
                true,
                TOKEN_CREATOR_SPLIT,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(registry);
        };
        
        // Mint tokens
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let treasury_cap = test_scenario::take_from_sender<TreasuryCap<TEST_TOKEN>>(&scenario);
            
            let mint_amount = 1000000000; // 10 tokens with 8 decimals
            
            user_token::mint_tokens<TEST_TOKEN>(
                &admin_cap,
                &mut treasury_cap,
                mint_amount,
                USER1,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_to_sender(&scenario, treasury_cap);
        };
        
        // Verify USER1 received the tokens
        test_scenario::next_tx(&mut scenario, USER1);
        {
            assert!(test_scenario::has_most_recent_for_address<Coin<TEST_TOKEN>>(USER1), 0);
            
            let coin = test_scenario::take_from_sender<Coin<TEST_TOKEN>>(&scenario);
            assert!(coin::value(&coin) == 1000000000, 0);
            
            test_scenario::return_to_sender(&scenario, coin);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test updating token commission settings
    #[test]
    fun test_update_commission() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create a user token first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let registry = test_scenario::take_shared<TokenRegistry>(&scenario);
            
            user_token::create_user_token<TEST_TOKEN>(
                &admin_cap,
                &mut registry,
                USER1,
                TEST_TOKEN {},
                TOKEN_DECIMALS,
                TOKEN_SYMBOL,
                TOKEN_NAME,
                TOKEN_DESCRIPTION,
                true,
                TOKEN_ICON_URL,
                true,
                TOKEN_COMMISSION,
                true,
                TOKEN_CREATOR_SPLIT,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(registry);
        };
        
        // Update token commission settings
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let ownership = test_scenario::take_from_sender<UserTokenOwnership<TEST_TOKEN>>(&scenario);
            let registry = test_scenario::take_shared<TokenRegistry>(&scenario);
            
            let new_commission = 700; // 7% in basis points
            let new_creator_split = 9000; // 90% in basis points
            
            user_token::update_commission<TEST_TOKEN>(
                &ownership,
                &mut registry,
                new_commission,
                new_creator_split,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify the update
            let token_type = user_token::token_id(&user_token::find_token_info(&registry, 
                                                  user_token::token_id(test_scenario::object_address(&ownership))));
            let (commission, creator_split, platform_split) = user_token::get_token_commission(&registry, token_type);
            
            assert!(commission == new_commission, 0);
            assert!(creator_split == new_creator_split, 0);
            assert!(platform_split == 10000 - new_creator_split, 0);
            
            test_scenario::return_to_sender(&scenario, ownership);
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
    
    // Test token swap and fee collection
    #[test]
    fun test_token_swap_and_fees() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create a user token first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let registry = test_scenario::take_shared<TokenRegistry>(&scenario);
            
            user_token::create_user_token<TEST_TOKEN>(
                &admin_cap,
                &mut registry,
                USER1,
                TEST_TOKEN {},
                TOKEN_DECIMALS,
                TOKEN_SYMBOL,
                TOKEN_NAME,
                TOKEN_DESCRIPTION,
                true,
                TOKEN_ICON_URL,
                true,
                TOKEN_COMMISSION,
                true,
                TOKEN_CREATOR_SPLIT,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(registry);
        };
        
        // Mint tokens
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let treasury_cap = test_scenario::take_from_sender<TreasuryCap<TEST_TOKEN>>(&scenario);
            
            let mint_amount = 1000000000; // 10 tokens with 8 decimals
            
            user_token::mint_tokens<TEST_TOKEN>(
                &admin_cap,
                &mut treasury_cap,
                mint_amount,
                USER2,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_to_sender(&scenario, treasury_cap);
        };
        
        // Get the FeeCollector object ID
        let fee_collector_id = 0; 
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let collector = test_scenario::take_shared<FeeCollector<TEST_TOKEN>>(&scenario);
            fee_collector_id = test_scenario::object_address(&collector);
            test_scenario::return_shared(collector);
        };
        
        // USER2 performs a token swap (using the FeeCollector as a proxy for the swap)
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let registry = test_scenario::take_shared<TokenRegistry>(&scenario);
            let fee_collector = test_scenario::take_shared_by_id<FeeCollector<TEST_TOKEN>>(
                &scenario, 
                fee_collector_id
            );
            let coin = test_scenario::take_from_sender<Coin<TEST_TOKEN>>(&scenario);
            
            let swap_amount = 100000000; // 1 token with 8 decimals
            
            user_token::swap<TEST_TOKEN>(
                &registry,
                &mut fee_collector,
                &mut coin,
                swap_amount,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify fees were collected
            let creator_fees = user_token::get_creator_available_fees(&fee_collector);
            let platform_fees = user_token::get_platform_available_fees(&fee_collector);
            
            // Expected: 5% fee = 5000000 (0.05 token)
            // Creator gets 80% of fee = 4000000 (0.04 token)
            // Platform gets 20% of fee = 1000000 (0.01 token)
            assert!(creator_fees == 4000000, 0);
            assert!(platform_fees == 1000000, 0);
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(fee_collector);
            test_scenario::return_to_sender(&scenario, coin);
        };
        
        // USER1 (creator) withdraws their fees
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let ownership = test_scenario::take_from_sender<UserTokenOwnership<TEST_TOKEN>>(&scenario);
            let fee_collector = test_scenario::take_shared_by_id<FeeCollector<TEST_TOKEN>>(
                &scenario, 
                fee_collector_id
            );
            
            user_token::withdraw_creator_fees<TEST_TOKEN>(
                &ownership,
                &mut fee_collector,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify fees were withdrawn
            assert!(user_token::get_creator_available_fees(&fee_collector) == 0, 0);
            
            test_scenario::return_to_sender(&scenario, ownership);
            test_scenario::return_shared(fee_collector);
        };
        
        // Verify USER1 received the fee coins
        test_scenario::next_tx(&mut scenario, USER1);
        {
            assert!(test_scenario::has_most_recent_for_address<Coin<TEST_TOKEN>>(USER1), 0);
            
            let coin = test_scenario::take_from_sender<Coin<TEST_TOKEN>>(&scenario);
            assert!(coin::value(&coin) == 4000000, 0); // 0.04 tokens
            
            test_scenario::return_to_sender(&scenario, coin);
        };
        
        // ADMIN withdraws platform fees
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let fee_collector = test_scenario::take_shared_by_id<FeeCollector<TEST_TOKEN>>(
                &scenario, 
                fee_collector_id
            );
            
            user_token::withdraw_platform_fees<TEST_TOKEN>(
                &admin_cap,
                &mut fee_collector,
                test_scenario::ctx(&mut scenario)
            );
            
            // Verify fees were withdrawn
            assert!(user_token::get_platform_available_fees(&fee_collector) == 0, 0);
            
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(fee_collector);
        };
        
        // Verify ADMIN received the fee coins
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            assert!(test_scenario::has_most_recent_for_address<Coin<TEST_TOKEN>>(ADMIN), 0);
            
            let coin = test_scenario::take_from_sender<Coin<TEST_TOKEN>>(&scenario);
            assert!(coin::value(&coin) == 1000000, 0); // 0.01 tokens
            
            test_scenario::return_to_sender(&scenario, coin);
        };
        
        test_scenario::end(scenario);
    }
    
    // For testing a second token type
    public struct USER2_TOKEN has drop {}
    
    // Test creating multiple user tokens
    #[test]
    fun test_multiple_tokens() {
        let scenario = test_scenario::begin(ADMIN);
        
        // Create token for USER1
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let registry = test_scenario::take_shared<TokenRegistry>(&scenario);
            
            user_token::create_user_token<TEST_TOKEN>(
                &admin_cap,
                &mut registry,
                USER1,
                TEST_TOKEN {},
                TOKEN_DECIMALS,
                TOKEN_SYMBOL,
                TOKEN_NAME,
                TOKEN_DESCRIPTION,
                true,
                TOKEN_ICON_URL,
                true,
                TOKEN_COMMISSION,
                true,
                TOKEN_CREATOR_SPLIT,
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(registry);
        };
        
        // Create token for USER2
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let registry = test_scenario::take_shared<TokenRegistry>(&scenario);
            
            user_token::create_user_token<USER2_TOKEN>(
                &admin_cap,
                &mut registry,
                USER2,
                USER2_TOKEN {},
                TOKEN_DECIMALS,
                b"USER2",
                b"User Two Token",
                b"A test token for User Two",
                true,
                TOKEN_ICON_URL,
                true,
                1000, // 10% commission
                true,
                7000, // 70% creator split
                test_scenario::ctx(&mut scenario)
            );
            
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(registry);
        };
        
        // Verify both tokens are in the registry
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let registry = test_scenario::take_shared<TokenRegistry>(&scenario);
            
            let token_ids = user_token::get_all_tokens(&registry);
            assert!(vector::length(&token_ids) == 2, 0);
            
            // USER1 has a token
            let (has_token1, token_info1) = user_token::get_user_token_info(&registry, USER1);
            assert!(has_token1, 0);
            assert!(user_token::user(&token_info1) == USER1, 0);
            
            // USER2 has a token
            let (has_token2, token_info2) = user_token::get_user_token_info(&registry, USER2);
            assert!(has_token2, 0);
            assert!(user_token::user(&token_info2) == USER2, 0);
            assert!(user_token::commission_bps(&token_info2) == 1000, 0);
            assert!(user_token::creator_split_bps(&token_info2) == 7000, 0);
            
            // The token IDs should be different
            assert!(user_token::token_id(&token_info1) != user_token::token_id(&token_info2), 0);
            
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }
}