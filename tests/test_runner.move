// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module mys::test_runner {
    use mys::profile_tests;
    use mys::post_tests;
    use mys::social_graph_tests;

    // This function can be run to execute all social network tests at once
    #[test]
    fun run_all_social_network_tests() {
        // The tests will be run automatically when the test runner is executed
        // This function exists primarily for documentation purposes
    }
}