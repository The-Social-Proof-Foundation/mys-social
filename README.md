# MySocial Contracts

A comprehensive decentralized social network built on the MySocial blockchain featuring advanced content monetization, governance, and social interactions.

## Published Contract

The contract is published on MySocial network with package ID:
```
0x000000000000000000000000000000000000000000000000000000000000d880
```

## Platform Overview

MySocial is a feature-rich decentralized social platform that combines traditional social networking with blockchain-native features like token trading, content monetization, decentralized governance, and proof-of-creativity systems.

## Core Modules

### 1. **Profile Management** (`profile.move`)
- **User Identity**: Create and manage user profiles with display names, bios, profile pictures
- **Username System**: Register unique usernames as NFTs with pricing tiers
- **Social Connections**: Link social media accounts (Twitter, GitHub, Instagram, etc.)
- **Profile Trading**: Buy/sell profiles with offers and automated fee distribution
- **Badge System**: Platform-issued verification and achievement badges
- **MyIP Integration**: Attach data monetization assets to profiles

**Key Features:**
- Profile ownership transfer
- Minimum offer amounts for profile sales
- Authorized service management
- Comprehensive social media linking

### 2. **Content Creation** (`post.move`)
- **Post Types**: Standard posts, comments, reposts, quote reposts, predictions
- **Rich Media**: Support for multiple media URLs, mentions, metadata
- **Interaction Controls**: Granular permissions for comments, reactions, reposts, quotes, tips
- **Prediction Markets**: Create prediction posts with betting and resolution
- **Content Moderation**: Platform-level content flagging and removal
- **Proof of Creativity Integration**: Automatic revenue redirection for derivative content

**Advanced Features:**
- Nested comment threads
- Reaction system with emoji/text responses
- Prediction betting with automatic payouts
- Revenue splitting for reposts and comments

### 3. **Proof of Creativity** (`proof_of_creativity.move`)
- **Content Analysis**: Oracle-based similarity detection for originality verification
- **PoC Badges**: Issue badges for original content
- **Revenue Redirection**: Automatic revenue routing from derivative to original creators
- **Community Disputes**: Vote-based system to challenge PoC decisions
- **Cross-Module Integration**: Seamless integration with posts and token trading

**Workflow:**
1. Oracle analyzes content for originality
2. Original content receives PoC badge
3. Derivative content gets revenue redirection rules
4. All tips/trading fees automatically split according to PoC analysis
5. Community can dispute decisions through voting

### 4. **Token Exchange** (`token_exchange.move`)
- **Dual Token System**: Profile tokens and post tokens with different economics
- **AMM Trading**: Quadratic pricing curve for token trading
- **Pre-Launch Auctions**: Viral content can launch tokens through community auctions
- **Automated PoC Integration**: Revenue redirection built into all trading functions
- **Fee Distribution**: Multi-tier fee system (creator, platform, treasury)

**Trading Features:**
- Buy/sell tokens with slippage protection
- Auction-based token launches for viral content
- Maximum holding limits to prevent concentration
- Dynamic pricing based on supply and demand

### 5. **Social Graph** (`social_graph.move`)
- **Follow System**: Decentralized follow/unfollow relationships
- **Global Registry**: Shared social graph across all platforms
- **Profile Integration**: Automatic follower/following count updates
- **Privacy Controls**: Integration with blocking systems

### 6. **Platform Management** (`platform.move`)
- **Multi-Platform Support**: Multiple social platforms can use the same contracts
- **Developer Tools**: Platform creation, moderation, user management
- **Governance Integration**: Platforms can opt into DAO governance
- **Treasury Management**: Platform-specific token treasuries
- **Badge Issuance**: Platforms can issue verification badges to users

**Platform Features:**
- User join/leave functionality
- Moderator management
- Content blocking and approval
- Token airdrops from platform treasuries

### 7. **Subscription Services** (`subscription.move`)
- **Profile Subscriptions**: Monthly subscription access to profile content
- **Auto-Renewal**: Gas-optimized automatic subscription renewals
- **Flexible Pricing**: Profile owners set their own subscription rates
- **Access Control**: Integration with content gating systems

### 8. **Data Monetization** (`my_ip.move`)
- **Encrypted Content**: Sell access to encrypted data using Seal encryption
- **Dual Pricing**: One-time purchases or subscription-based access
- **Rich Metadata**: Comprehensive data categorization and discovery
- **Access Management**: Granular control over who can access content
- **Revenue Optimization**: Multiple monetization strategies per data asset

**MyIP Features:**
- Time-range data for analytics
- Geographic and quality metadata
- Subscription duration flexibility
- Free access grants for promotion

### 9. **Decentralized Governance** (`governance.move`)
- **Multi-Registry System**: Separate governance for ecosystem, reputation, community notes
- **Delegate Council**: Elected representatives for proposal review
- **Community Voting**: Quadratic voting system for final decisions
- **Anonymous Voting**: Privacy-preserving vote encryption
- **Reward Distribution**: Token incentives for participation

**Governance Process:**
1. Submit proposals with token stake
2. Delegate council reviews and approves for community voting
3. Community votes with quadratic cost scaling
4. Automatic reward distribution to winning voters
5. Implementation tracking and verification

### 10. **User Safety** (`block_list.move`)
- **Granular Blocking**: Block users from seeing your content or interacting
- **Platform-Level Blocks**: Platforms can block users from their ecosystem
- **Cross-Module Integration**: Blocking affects all interactions (tips, comments, trading)

### 11. **System Upgrades** (`upgrade.move`)
- **Version Management**: Controlled upgrades across all modules
- **Migration Support**: Automatic object migration to new versions
- **Admin Controls**: Secure upgrade authorization system

## Key Innovations

### Integrated Revenue Redirection
- **Seamless PoC Integration**: All revenue streams (tips, token trading fees) automatically redirect based on content originality
- **Multi-Level Splitting**: Complex revenue sharing between original creators, derivative creators, platforms, and treasury
- **Real-Time Analysis**: Oracle integration for immediate PoC decisions

### Advanced Token Economics
- **Viral Threshold Auctions**: Only viral content can launch tokens through community auctions
- **Dynamic Pricing**: Quadratic curves prevent manipulation while enabling price discovery
- **Cross-Module Integration**: Tokens seamlessly integrate with all platform features

### Comprehensive Governance
- **Specialized Registries**: Different governance systems for different types of decisions
- **Delegate Democracy**: Hybrid system combining representative and direct democracy
- **Economic Incentives**: Token rewards align voter incentives with platform health

## Quick Start

### Prerequisites
- [MySocial CLI](https://docs.mysocial.io/cli-install) installed
- An account with MYS coins for gas and transactions

### Basic Setup

1. **Create a Profile**
```bash
myso client call --package 0x000000000000000000000000000000000000000000000000000000000000d880 \
  --module profile --function create_profile \
  --args "Your Name" "your_username" "Your bio" "https://example.com/profile.jpg" "https://example.com/cover.jpg" \
  --gas-budget 1000000000
```

2. **Join a Platform**
```bash
myso client call --package 0x000000000000000000000000000000000000000000000000000000000000d880 \
  --module platform --function join_platform \
  --args [REGISTRY_ID] [PLATFORM_ID] \
  --gas-budget 1000000000
```

3. **Create a Post**
```bash
myso client call --package 0x000000000000000000000000000000000000000000000000000000000000d880 \
  --module post --function create_post \
  --args [REGISTRY_ID] [PLATFORM_ID] [BLOCK_LIST_ID] [CONFIG_ID] "Hello MySocial!" \
  --gas-budget 1000000000
```

### Advanced Features

**Create a Prediction Post:**
```bash
myso client call --package 0x000000000000000000000000000000000000000000000000000000000000d880 \
  --module post --function create_prediction_post \
  --args [CONFIG_ID] [ADMIN_CAP] [REGISTRY_ID] [PLATFORM_ID] [BLOCK_LIST_ID] \
  "Who will win the game?" '["Team A", "Team B"]' \
  --gas-budget 1000000000
```

**Subscribe to a Profile:**
```bash
myso client call --package 0x000000000000000000000000000000000000000000000000000000000000d880 \
  --module subscription --function subscribe_to_profile \
  --args [SERVICE_ID] [PAYMENT_COIN] true 3 [CLOCK_ID] \
  --gas-budget 1000000000
```

### Social Proof of Truth (SPoT)
SPoT enables truth markets on posts by splitting each bet between AMM SPT buys and an escrow used for clean payouts.

1) Create a SPoT record for a post
```bash
myso client call --package 0x...d880 \
  --module social_proof_of_truth --function create_spot_record_for_post \
  --args [SPOT_CONFIG_ID] [POST_ID] \
  --gas-budget 1000000000
```

2) Place a bet (auto‑init post SPT pool if missing)
```bash
myso client call --package 0x...d880 \
  --module social_proof_of_truth --function place_spot_bet_auto_init \
  --args [SPOT_CONFIG_ID] [SPT_REGISTRY_ID] [SPT_CONFIG_ID] [SPOT_RECORD_ID] [POST_ID] \
        [PLATFORM_ID] [BLOCK_LIST_REGISTRY_ID] [PAYMENT_COIN] true [AMOUNT] \
  --gas-budget 1000000000
```

3) Resolve via Oracle (YES/NO + confidence)
```bash
myso client call --package 0x...d880 \
  --module social_proof_of_truth --function oracle_resolve \
  --args [SPOT_CONFIG_ID] [SPOT_RECORD_ID] [POST_ID] true 9000 \
  --gas-budget 1000000000
```

4) If confidence is below threshold, finalize via DAO (YES/NO/DRAW/UNAPPLICABLE)
```bash
myso client call --package 0x...d880 \
  --module social_proof_of_truth --function finalize_via_dao \
  --args [SPOT_CONFIG_ID] [SPOT_RECORD_ID] [POST_ID] 3 \
  --gas-budget 1000000000
```

Notes:
- Auto‑init requires `social_proof_tokens` config `allow_auto_pool_init = true` and post not opted‑out.
- Bets split: β to AMM buy (default 30%), (1−β) to escrow; payouts are pro‑rata from escrow minus 1% fee split 50/50 between platform/chain treasuries.

**Submit a Governance Proposal:**
```bash
myso client call --package 0x000000000000000000000000000000000000000000000000000000000000d880 \
  --module governance --function submit_ecosystem_proposal \
  --args [REGISTRY_ID] "Proposal Title" "Detailed description" [PAYMENT_COIN] \
  --gas-budget 1000000000
```

## Economic Model

### Revenue Streams
1. **Transaction Fees**: Trading, tipping, subscription fees
2. **Platform Fees**: Content creation, platform services
3. **Governance Fees**: Proposal submission, voting costs
4. **Token Trading**: AMM fees and auction revenues

### Revenue Distribution
- **Creators**: 60-80% of revenue (varies by activity)
- **Original Creators**: Automatic redirection via PoC system
- **Platforms**: 25% of transaction fees
- **Ecosystem Treasury**: 25% of transaction fees
- **Governance Participants**: Voting rewards and proposal stakes

## Technical Architecture

### Modular Design
- **Separation of Concerns**: Each module handles specific functionality
- **Cross-Module Integration**: Seamless data sharing and function calls
- **Upgrade Path**: Independent module upgrades without system downtime

### Security Features
- **Permission Systems**: Granular access controls throughout
- **Economic Security**: Token staking for important actions
- **Community Oversight**: Dispute resolution and governance checks

### Scalability
- **Efficient Data Structures**: Optimized storage and retrieval
- **Event-Driven Architecture**: Off-chain indexing and caching
- **Parallel Processing**: Independent module operations

## Testing

Run the comprehensive test suite:

```bash
# Build the project
myso move build

# Run all tests
myso move test

# Run specific module tests
myso move test --filter test_token_exchange
myso move test --filter test_proof_of_creativity
myso move test --filter test_governance
```

## Integration Examples

### Platform Integration
Platforms can integrate MySocial contracts to add:
- Decentralized user profiles and social graphs
- Content monetization through tipping and subscriptions
- Token trading for creator and platform tokens
- Community governance for platform decisions
- Proof-of-creativity revenue sharing

### DApp Integration
Applications can build on MySocial for:
- Social login and identity
- Content verification and originality checking
- Micropayments and subscriptions
- Community governance and voting
- Data monetization infrastructure

## Development

### Building Locally
```bash
cd crates/mys-framework/packages/mys-social
myso move build
```

### Publishing Updates
```bash
myso client publish --gas-budget 200000000000
```

### Upgrading Contracts
The upgrade system allows for seamless contract updates while preserving user data and maintaining backward compatibility.

## License

Copyright (c) The Social Proof Foundation, LLC.  
SPDX-License-Identifier: Apache-2.0
