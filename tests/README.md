# MySocial Network Tests

This directory contains test modules for the MySocial network features. These tests verify the functionality of the social network smart contracts.

## Test Modules

- `profile_tests.move`: Tests for profile creation and management
- `post_tests.move`: Tests for posts, comments, likes, and other content interactions
- `social_graph_tests.move`: Tests for follow/unfollow functionality and social relationships
- `my_ip_tests.move`: Tests for intellectual property registration
- `proof_of_creativity_tests.move`: Tests for creativity proof verification system
- `test_runner.move`: Helper module for running all tests together

## Running Tests

You can run the tests using the MySocial Move testing framework. From the root of the repository, use the following commands:

### Run All Tests

To run all tests in the social network module:

```bash
myso move test
```

### Run Specific Test Modules

To run tests for a specific module:

```bash
# Run profile tests
myso move test --filter profile_tests

# Run post tests
myso move test --filter post_tests

# Run social graph tests
myso move test --filter social_graph_tests

# Run intellectual property tests
myso move test --filter my_ip_tests

# Run proof of creativity tests
myso move test --filter proof_of_creativity_tests
```

### Run Individual Tests

To run a single test function:

```bash
# Example: Run just the profile creation test
myso move test --filter test_create_profile
```

## Test Coverage

The test suite covers the following key functionality:

1. **Profile Management**
   - Profile creation
   - Profile updating
   - Ownership verification

2. **Content Interactions**
   - Post creation
   - Comment creation
   - Like/unlike functionality
   - Tipping content creators

3. **Social Graph**
   - Follow/unfollow functionality
   - Relationship tracking
   - Validation rules (e.g., preventing self-follows)

4. **Intellectual Property**
   - IP registration
   - Proof of creativity creation
   - Verification workflows
   - Provider registration and authorization

## Test Status

| Module | Status | Coverage |
|--------|--------|----------|
| profile | ✅ Complete | High |
| social_graph | ✅ Complete | High |
| post | ✅ Complete | High |
| my_ip | ✅ Complete | Medium |
| proof_of_creativity | ✅ Complete | High |
| advertise | ⚠️ Partial | Low |
| user_token | ⚠️ Partial | Low |
| ai_agent_integration | ⚠️ Minimal | Low |
| ai_agent_mpc | ⚠️ Minimal | Low |
| ai_data_monetization | ⚠️ Minimal | Low |

## Adding New Tests

When adding new features to the social network modules, please add corresponding tests that:

1. Test the happy path (expected successful behavior)
2. Test edge cases and failure scenarios
3. Use the test_scenario framework to simulate multi-transaction sequences

Follow the existing patterns in the test modules for consistency.