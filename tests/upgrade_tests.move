// Copyright (c) MySocial, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module social_contracts::upgrade_tests {
    use social_contracts::upgrade;

    #[test]
    /// Test utility function for creating properly-sized digests
    fun test_create_test_digest() {
        // Test with shorter than 32 bytes
        let input_short = b"too short";
        let result_short = upgrade::create_test_digest(input_short);
        assert!(std::vector::length(&result_short) == 32, 0);
        
        // Test with exactly 32 bytes
        let input_exact = create_test_digest();
        let result_exact = upgrade::create_test_digest(input_exact);
        assert!(std::vector::length(&result_exact) == 32, 0);
        
        // Test with longer than 32 bytes
        let mut input_long = std::vector::empty<u8>();
        let mut i = 0;
        while (i < 64) {
            std::vector::push_back(&mut input_long, (i as u8));
            i = i + 1;
        };
        let result_long = upgrade::create_test_digest(input_long);
        assert!(std::vector::length(&result_long) == 32, 0);
    }
    
    /// Create a test 32-byte digest
    fun create_test_digest(): vector<u8> {
        let mut result = std::vector::empty<u8>();
        let mut i = 0;
        while (i < 32) {
            std::vector::push_back(&mut result, (i as u8));
            i = i + 1;
        };
        result
    }
} 