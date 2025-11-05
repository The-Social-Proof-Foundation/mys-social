# MySocial Network Tests

This directory contains test modules for the MySocial network features. These tests verify the functionality of the social network smart contracts.

## Test Modules

- `profile_tests.move`: Tests for profile creation and management
- `post_tests.move`: Tests for posts, comments, likes, and other content interactions
- `social_graph_tests.move`: Tests for follow/unfollow functionality and social relationships
- `mydata_tests.move`: Tests for data monetization and management
- `platform_tests.move`: Tests for platform creation, administration, and badge management
- `block_list_tests.move`: Tests for user blocking functionality
- `governance_tests.move`: Tests for governance proposals and voting
- `token_exchange_tests.move`: Tests for token exchange functionality
- `upgrade_tests.move`: Tests for contract upgrade mechanisms

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
myso move test --filter mydata_tests

# Run platform tests
myso move test --filter platform_tests

# Run block list tests
myso move test --filter block_list_tests

# Run governance tests
myso move test --filter governance_tests

# Run token exchange tests
myso move test --filter token_exchange_tests

# Run upgrade tests
myso move test --filter upgrade_tests
```

### Run Individual Tests

To run a single test function:

```bash
# Example: Run just the profile creation test
myso move test --filter test_create_profile

# Example: Run just the license creation test
myso move test --filter test_create_license
```

## Test Coverage

The test suite covers the following key functionality:

1. **Profile Management**
   - Profile creation
   - Profile updating
   - Ownership verification
   - Profile transfers and offers

2. **Content Interactions**
   - Post creation
   - Comment creation
   - Like/unlike functionality
   - Tipping content creators
   - Reactions and prediction posts

3. **Social Graph**
   - Follow/unfollow functionality
   - Relationship tracking
   - Validation rules (e.g., preventing self-follows)

4. **Intellectual Property**
   - License creation with various permission models
   - License state management (active, expired, revoked)
   - License transfers and ownership verification
   - Revenue recipient configuration
   - Administrative capability management
   - License permission validation (commercial use, derivatives, attribution, etc.)
   - Creative Commons license templates
   - Custom license flag configuration

5. **Platform Management**
   - Platform creation and administration
   - Moderator management
   - Badge assignment and revocation
   - Platform approval workflows

6. **Block List Functionality**
   - Creating block lists
   - Blocking and unblocking wallets
   - Block list validation

7. **Governance**
   - Proposal creation and management
   - Voting mechanisms
   - Proposal execution
   - Delegate selection and term management

8. **Token Exchange**
   - Token auction flows
   - Buying and selling tokens
   - Price calculations
   - Fee distribution

9. **Upgrade Mechanisms**
   - Version management
   - Migration patterns
   - Admin capability management

## Test Status

| Module | Status | Coverage |
|--------|--------|----------|
| profile | ✅ Complete | High |
| social_graph | ✅ Complete | High |
| post | ✅ Complete | High |
| mydata | ✅ Complete | High |
| platform | ✅ Complete | High |
| block_list | ✅ Complete | High |
| governance | ✅ Complete | High |
| token_exchange | ✅ Complete | Medium |
| upgrade | ✅ Complete | Medium |

## Adding New Tests

When adding new features to the social network modules, please add corresponding tests that:

1. Test the happy path (expected successful behavior)
2. Test edge cases and failure scenarios
3. Use the test_scenario framework to simulate multi-transaction sequences

Follow the existing patterns in the test modules for consistency.