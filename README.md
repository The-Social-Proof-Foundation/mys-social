# MySocial Contracts

This repository contains the smart contracts for the MySocial platform, a decentralized social network built on the MySocial blockchain.

## Published Contract

The contract is published on MySocial network with package ID:
```
0xf16b6567d925341ab29edcf9e0dd743530f235083b2ac2603dbe6e37832eafef
```

## Key Components

The MySocial platform consists of several interconnected modules:

1. **Profile** - Manages user profiles and identity
2. **Name Service** - Handles username registration and management
3. **Post** - Enables creating and sharing social content
4. **Social Graph** - Manages connections between users (follow/unfollow)
5. **Registry** - Provides standardized registry patterns for various components

## Interacting with the Contract

### Prerequisites

- [MySocial CLI](https://docs.mysocial.io/cli-install) installed
- An account with MYS coins for gas and transactions

### Basic Usage

#### 1. Create a Name Registry

The first step is to create a shared name registry that stores all usernames:

```bash
# Create and share name registry
myso client call --package 0xf16b6567d925341ab29edcf9e0dd743530f235083b2ac2603dbe6e37832eafef --module name_service --function create_and_share_registry --gas-budget 1000000000
```

Save the generated registry ID from the transaction output.

#### 2. Create a Profile

Create your profile with display name, bio, and profile picture URL:

```bash
# Create profile
myso client call --package 0xf16b6567d925341ab29edcf9e0dd743530f235083b2ac2603dbe6e37832eafef --module profile --function create_profile --args "Your Name" "Your bio" "https://example.com/profile.jpg" --gas-budget 1000000000
```

Save your profile ID from the transaction output.

#### 3. Register a Username

Register a username and assign it to your profile:

```bash
# Register and assign username
myso client call --package 0xf16b6567d925341ab29edcf9e0dd743530f235083b2ac2603dbe6e37832eafef --module name_service --function register_and_assign_username --args [REGISTRY_ID] [PROFILE_ID] "username" [COIN_OBJECT_ID] 1 [CLOCK_OBJECT_ID] --gas-budget 1000000000
```

Replace:
- `[REGISTRY_ID]` with the ID of the name registry
- `[PROFILE_ID]` with your profile ID
- `"username"` with your desired username
- `[COIN_OBJECT_ID]` with an object ID of a MYS coin you own
- `[CLOCK_OBJECT_ID]` with the system clock ID (usually `0x6`)

#### 4. Update Profile

Update your profile information:

```bash
# Update profile
myso client call --package 0xf16b6567d925341ab29edcf9e0dd743530f235083b2ac2603dbe6e37832eafef --module profile --function update_profile --args [PROFILE_ID] "New Name" "Updated bio" "https://example.com/new-profile.jpg" --gas-budget 1000000000
```

#### 5. Create a Post

Create a social post:

```bash
# Create post (simplified example)
myso client call --package 0xf16b6567d925341ab29edcf9e0dd743530f235083b2ac2603dbe6e37832eafef --module post --function create_post --args [PROFILE_ID] "Hello World!" "" "" --gas-budget 1000000000
```

### Additional Resources

For more complex functionality including social graph management, content monetization, and platform integrations, refer to the module source code and tests. The contract includes:

- Profile and identity management
- Username registration and NFT management
- Social posting and content sharing
- Reputation and token systems
- Platform integration and monetization options

## Quick Testing Script

For quick testing, run the provided shell script:

```bash
./interact_with_social_contract.sh
```

## Username Pricing

Usernames are priced based on length:
- Ultra short (2-4 chars): 1,000 MYS
- Short (5-7 chars): 50 MYS
- Medium (8-12 chars): 20 MYS  
- Long (13+ chars): 10 MYS

## Development

To build and test the contracts locally:

```bash
# Build the project
cd /path/to/mys-social
myso move build

# Run tests
myso move test
```

## License

Copyright (c) MySocial, Inc.
SPDX-License-Identifier: Apache-2.0