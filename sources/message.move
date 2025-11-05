// Copyright (c) The Social Proof Foundation, LLC.
// SPDX-License-Identifier: Apache-2.0

/// On-chain messaging protocol for MySocial blockchain
/// Stores only message digests (hashes) while keeping full content off-chain
/// Features: idempotency, message ordering, replay protection, access control, rate limiting

#[allow(unused_const, duplicate_alias)]
module social_contracts::message {
    use std::option::{Self, Option};
    
    use mys::{
        object::{Self, UID},
        tx_context::{Self, TxContext},
        transfer,
        event,
        table::{Self, Table},
        vec_map::{Self, VecMap},
        clock::{Self, Clock},
        coin::{Self, Coin},
        balance::{Self, Balance},
        mys::MYS
    };

    use social_contracts::profile::{Self, Profile};
    use social_contracts::platform::{Self, Platform};
    use social_contracts::social_proof_tokens::{Self as spt, SocialProofTokensConfig};

    // === Error Codes ===
    
    const E_PAUSED: u64 = 1;
    const E_NOT_MEMBER: u64 = 2;
    const E_NOT_ADMIN: u64 = 3;
    const E_ALREADY_MEMBER: u64 = 4;
    const E_DEDUPE_USED: u64 = 5;
    const E_NONCE_USED: u64 = 6;
    const E_BAD_SEQ: u64 = 7;
    const E_NO_MSG: u64 = 8;
    const E_NOT_FOUND: u64 = 9;
    const E_ROLE_INVALID: u64 = 10;
    const E_FORBIDDEN: u64 = 11;
    const E_RATE_LIMIT: u64 = 12;
    const E_INSUFFICIENT_PAYMENT: u64 = 13;
    const E_NOT_PAID_MESSAGE: u64 = 14;
    const E_PAYMENT_EXPIRED: u64 = 15;
    const E_PAYMENT_ALREADY_CLAIMED: u64 = 16;
    const E_REPLY_TOO_SHORT: u64 = 17;

    // === Roles ===
    
    const ROLE_MEMBER: u8 = 0;
    const ROLE_MOD: u8 = 1;
    const ROLE_ADMIN: u8 = 2;

    // === Conversation Types ===
    
    const CONV_DM: u8 = 0;
    const CONV_GROUP: u8 = 1;
    const CONV_CHANNEL: u8 = 2;

    // === Message Types ===
    
    const MSG_TEXT: u8 = 0;
    const MSG_REPLY: u8 = 1;
    const MSG_SYSTEM: u8 = 2;

    // === Paid Messaging Constants ===
    
    const MIN_REPLY_CHARS: u32 = 6; // Minimum characters to claim payment
    const PAYMENT_EXPIRATION_EPOCHS: u64 = 30; // Payment expires after 30 epochs
    
    // Fee percentages (in basis points, 10000 = 100%)
    const PAID_MSG_PLATFORM_FEE_BPS: u64 = 250; // 2.5% to platform
    const PAID_MSG_TREASURY_FEE_BPS: u64 = 250; // 2.5% to ecosystem treasury
    const PAID_MSG_TOTAL_FEE_BPS: u64 = 500; // 5% total fee

    // === Registry: Global shared protocol state ===
    
    public struct Registry has key {
        id: UID,
        admin: address,
        relayer: address,
        paused: bool,
        version: u32,
        // Rate limit defaults (tumbling window)
        rl_window_secs: u64,
        rl_per_user_per_window: u32,
        rl_per_conv_per_window: u32,
    }

    // === Conversation: Owned by creator, holds messages and members ===
    
    public struct Conversation has key {
        id: UID,
        kind: u8, // DM, GROUP, CHANNEL
        next_seq: u64, // Next message sequence number
        meta_hash: vector<u8>, // Hash of off-chain metadata (name, avatar, etc)
        roles: Table<address, u8>, // Member roles
        members: Table<address, bool>, // Active members
        messages: Table<u64, MessageDigest>, // seq -> message
        used_dedupe: Table<vector<u8>, bool>, // Dedupe keys already used
        nonces: Table<address, Table<u128, bool>>, // Per-member nonce tracking
        reactions: Table<u64, Table<u32, u32>>, // seq -> (emoji_code -> count)
        pins: Table<u64, bool>, // Pinned messages
        delivered: VecMap<address, u64>, // Last delivered seq per member
        read: VecMap<address, u64>, // Last read seq per member
        flags: u64, // Feature flags
        // Rate limit config (0 = inherit from Registry)
        rl_window_secs: u64,
        rl_per_user_per_window: u32,
        rl_per_conv_per_window: u32,
        // Rate limit state
        rl_window_start: u64, // Window start timestamp
        rl_conv_count: u32, // Total messages in current window
        rl_user_counts: Table<address, u32>, // Per-user messages in current window
        rl_active_users: vector<address>, // Track users with active counts in window
        // Paid messaging escrow
        paid_msg_escrow: Table<u64, PaidMessageEscrow>, // seq -> escrow
    }

    // === MessageDigest: Stored on-chain, references off-chain content ===
    
    public struct MessageDigest has store, copy, drop {
        seq: u64,
        sender: address,
        kind: u8, // TEXT, REPLY, SYSTEM
        parent: u64, // For replies (0 if none)
        digest_hash: vector<u8>, // Hash of message content
        media_batch_hash: vector<u8>, // Hash of media attachments
        key_ref: vector<u8>, // Encrypted key reference for E2EE
        edit_seq: u32, // Edit version (0 = original)
        client_ts: u64, // Client-side timestamp
        server_ts: u64, // Server-side timestamp
        flags: u32, // Message-specific flags
        char_count: Option<u32>, // Character count for payment validation (only for paid messages)
        is_paid: bool, // Whether this is a paid message
    }

    // === PaidMessageEscrow: Holds payment until reply conditions met ===
    
    public struct PaidMessageEscrow has store {
        payer: address, // Who paid to send the message
        recipient: address, // Who should receive payment (profile owner)
        amount: u64, // Total payment amount
        escrowed_balance: Balance<MYS>, // Escrowed funds
        created_epoch: u64, // When the payment was made
        claimed: bool, // Whether payment has been claimed
        parent_seq: u64, // The paid message seq number
    }

    // === Events ===
    
    public struct ConversationCreated has copy, drop {
        conv: address,
        kind: u8,
        creator: address,
    }

    public struct ParticipantsAdded has copy, drop {
        conv: address,
        count: u32,
    }

    public struct ParticipantsRemoved has copy, drop {
        conv: address,
        count: u32,
    }

    public struct RoleChanged has copy, drop {
        conv: address,
        who: address,
        role: u8,
    }

    public struct ConversationMetaSet has copy, drop {
        conv: address,
        meta_hash: vector<u8>,
    }

    public struct MessageSent has copy, drop {
        conv: address,
        seq: u64,
        sender: address,
        kind: u8,
    }

    public struct MessageEdited has copy, drop {
        conv: address,
        seq: u64,
        edit_seq: u32,
    }

    public struct MessageTombstoned has copy, drop {
        conv: address,
        seq: u64,
        reason: u8,
    }

    public struct DeliveredAck has copy, drop {
        conv: address,
        member: address,
        upto: u64,
    }

    public struct ReadAck has copy, drop {
        conv: address,
        member: address,
        upto: u64,
    }

    public struct Reacted has copy, drop {
        conv: address,
        seq: u64,
        member: address,
        code: u32,
        op: u8, // 0=remove, 1=add
    }

    public struct Pinned has copy, drop {
        conv: address,
        seq: u64,
        on: bool,
    }

    public struct KeyRotated has copy, drop {
        conv: address,
        version: u32,
    }

    public struct MemberKeySubmitted has copy, drop {
        conv: address,
        member: address,
    }

    public struct Moderation has copy, drop {
        conv: address,
        seq: u64,
        reason: u8,
    }

    public struct Paused has copy, drop {
        on: bool,
    }

    public struct VersionSet has copy, drop {
        version: u32,
    }

    public struct RateLimitsSet has copy, drop {
        conv: address,
        window_secs: u64,
        per_user: u32,
        per_conv: u32,
    }

    public struct PaidMessageSent has copy, drop {
        conv: address,
        seq: u64,
        payer: address,
        recipient: address,
        amount: u64,
        created_epoch: u64,
    }

    public struct PaidMessageReplied has copy, drop {
        conv: address,
        paid_msg_seq: u64,
        reply_seq: u64,
        recipient: address,
        reply_char_count: u32,
    }

    public struct PaymentClaimed has copy, drop {
        conv: address,
        seq: u64,
        recipient: address,
        amount: u64,
        platform_fee: u64,
        treasury_fee: u64,
        net_amount: u64,
        claimed_epoch: u64,
    }

    public struct PaymentRefunded has copy, drop {
        conv: address,
        seq: u64,
        payer: address,
        amount: u64,
        refunded_epoch: u64,
        reason: u8, // 0=expired, 1=manual
    }

    // === Admin / Registry Functions ===

    /// Bootstrap initialization - creates the messaging registry (called during genesis)
    public(package) fun bootstrap_init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);
        let registry = Registry {
            id: object::new(ctx),
            admin,
            relayer: admin, // Default to admin, can be changed later
            paused: false,
            version: 1,
            // Default rate limits (can be changed by admin)
            rl_window_secs: 60,          // 60 second windows
            rl_per_user_per_window: 10,  // 10 messages per user per window
            rl_per_conv_per_window: 100, // 100 messages per conversation per window
        };
        transfer::share_object(registry);
    }

    /// Update relayer address (admin only)
    public entry fun set_relayer(
        registry: &mut Registry,
        new_relayer: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, E_NOT_ADMIN);
        registry.relayer = new_relayer;
    }

    /// Pause/unpause the protocol (admin only)
    public entry fun pause(
        registry: &mut Registry,
        on: bool,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, E_NOT_ADMIN);
        registry.paused = on;
        event::emit(Paused { on });
    }

    /// Update protocol version (admin only)
    public entry fun set_version(
        registry: &mut Registry,
        version: u32,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, E_NOT_ADMIN);
        registry.version = version;
        event::emit(VersionSet { version });
    }

    /// Transfer admin privileges (admin only)
    public entry fun transfer_admin(
        registry: &mut Registry,
        new_admin: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, E_NOT_ADMIN);
        registry.admin = new_admin;
    }

    // === Conversation & ACL Functions ===

    /// Create a new conversation (owned by creator)
    public entry fun create_conversation(
        registry: &Registry,
        kind: u8,
        meta_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(!registry.paused, E_PAUSED);
        let sender = tx_context::sender(ctx);

        let mut conv = Conversation {
            id: object::new(ctx),
            kind,
            next_seq: 1,
            meta_hash,
            roles: table::new(ctx),
            members: table::new(ctx),
            messages: table::new(ctx),
            used_dedupe: table::new(ctx),
            nonces: table::new(ctx),
            reactions: table::new(ctx),
            pins: table::new(ctx),
            delivered: vec_map::empty(),
            read: vec_map::empty(),
            flags: 0,
            rl_window_secs: 0, // Inherit from Registry
            rl_per_user_per_window: 0,
            rl_per_conv_per_window: 0,
            rl_window_start: 0,
            rl_conv_count: 0,
            rl_user_counts: table::new(ctx),
            rl_active_users: vector::empty(),
            paid_msg_escrow: table::new(ctx),
        };

        let conv_addr = object::uid_to_address(&conv.id);

        // Add creator as admin
        table::add(&mut conv.roles, sender, ROLE_ADMIN);
        table::add(&mut conv.members, sender, true);

        event::emit(ConversationCreated {
            conv: conv_addr,
            kind,
            creator: sender,
        });

        transfer::transfer(conv, sender);
    }

    /// Add participants to conversation (admin/mod only)
    public entry fun add_participants(
        conv: &mut Conversation,
        participants: vector<address>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_role_at_least(conv, sender, ROLE_MOD);

        let len = vector::length(&participants);
        let mut i = 0;
        let mut added = 0u32;

        while (i < len) {
            let addr = *vector::borrow(&participants, i);
            if (!table::contains(&conv.members, addr)) {
                table::add(&mut conv.roles, addr, ROLE_MEMBER);
                table::add(&mut conv.members, addr, true);
                added = added + 1;
            };
            i = i + 1;
        };

        event::emit(ParticipantsAdded {
            conv: object::uid_to_address(&conv.id),
            count: added,
        });
    }

    /// Remove participants from conversation (admin only)
    public entry fun remove_participants(
        conv: &mut Conversation,
        participants: vector<address>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_role_at_least(conv, sender, ROLE_ADMIN);

        let len = vector::length(&participants);
        let mut i = 0;
        let mut removed = 0u32;

        while (i < len) {
            let addr = *vector::borrow(&participants, i);
            if (table::contains(&conv.members, addr)) {
                table::remove(&mut conv.roles, addr);
                table::remove(&mut conv.members, addr);
                removed = removed + 1;
            };
            i = i + 1;
        };

        event::emit(ParticipantsRemoved {
            conv: object::uid_to_address(&conv.id),
            count: removed,
        });
    }

    /// Leave a conversation (self-removal)
    public entry fun leave_conversation(
        conv: &mut Conversation,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&conv.members, sender), E_NOT_MEMBER);

        table::remove(&mut conv.roles, sender);
        table::remove(&mut conv.members, sender);

        event::emit(ParticipantsRemoved {
            conv: object::uid_to_address(&conv.id),
            count: 1,
        });
    }

    /// Set member role (admin only)
    public entry fun set_role(
        conv: &mut Conversation,
        member: address,
        role: u8,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_role_at_least(conv, sender, ROLE_ADMIN);
        assert!(table::contains(&conv.members, member), E_NOT_MEMBER);
        assert!(role <= ROLE_ADMIN, E_ROLE_INVALID);

        *table::borrow_mut(&mut conv.roles, member) = role;

        event::emit(RoleChanged {
            conv: object::uid_to_address(&conv.id),
            who: member,
            role,
        });
    }

    /// Update conversation metadata hash (admin only)
    public entry fun set_conv_meta(
        conv: &mut Conversation,
        meta_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_role_at_least(conv, sender, ROLE_ADMIN);

        conv.meta_hash = meta_hash;

        event::emit(ConversationMetaSet {
            conv: object::uid_to_address(&conv.id),
            meta_hash,
        });
    }

    // === Idempotency / Sequencing Functions ===

    /// Pre-register a nonce for batch operations
    public entry fun use_nonce(
        conv: &mut Conversation,
        nonce: u128,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&conv.members, sender), E_NOT_MEMBER);

        // Initialize per-member nonce table if needed
        if (!table::contains(&conv.nonces, sender)) {
            table::add(&mut conv.nonces, sender, table::new(ctx));
        };

        let member_nonces = table::borrow_mut(&mut conv.nonces, sender);
        assert!(!table::contains(member_nonces, nonce), E_NONCE_USED);
        table::add(member_nonces, nonce, true);
    }

    /// Pre-mark dedupe key as used
    public entry fun mark_dedupe(
        conv: &mut Conversation,
        dedupe_key: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_role_at_least(conv, sender, ROLE_MOD);
        assert!(!table::contains(&conv.used_dedupe, dedupe_key), E_DEDUPE_USED);
        table::add(&mut conv.used_dedupe, dedupe_key, true);
    }

    // === Send / Edit / Tombstone Functions ===

    /// Send a new message with rate limit enforcement
    public entry fun send_message(
        registry: &Registry,
        conv: &mut Conversation,
        kind: u8,
        parent: u64,
        digest_hash: vector<u8>,
        media_batch_hash: vector<u8>,
        key_ref: vector<u8>,
        client_ts: u64,
        dedupe_key: vector<u8>,
        nonce: u128,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!registry.paused, E_PAUSED);
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&conv.members, sender), E_NOT_MEMBER);

        // Check dedupe
        assert!(!table::contains(&conv.used_dedupe, dedupe_key), E_DEDUPE_USED);
        table::add(&mut conv.used_dedupe, dedupe_key, true);

        // Check nonce
        if (!table::contains(&conv.nonces, sender)) {
            table::add(&mut conv.nonces, sender, table::new(ctx));
        };
        let member_nonces = table::borrow_mut(&mut conv.nonces, sender);
        assert!(!table::contains(member_nonces, nonce), E_NONCE_USED);
        table::add(member_nonces, nonce, true);

        // Enforce rate limits with tumbling window
        enforce_rate_limits(registry, conv, sender, clock);

        // Assign sequence number
        let seq = conv.next_seq;
        conv.next_seq = seq + 1;

        // Create message digest
        let msg = MessageDigest {
            seq,
            sender,
            kind,
            parent,
            digest_hash,
            media_batch_hash,
            key_ref,
            edit_seq: 0,
            client_ts,
            server_ts: clock::timestamp_ms(clock) / 1000,
            flags: 0,
            char_count: option::none(),
            is_paid: false,
        };

        table::add(&mut conv.messages, seq, msg);

        event::emit(MessageSent {
            conv: object::uid_to_address(&conv.id),
            seq,
            sender,
            kind,
        });
    }

    /// Edit an existing message (sender only)
    public entry fun edit_message(
        conv: &mut Conversation,
        seq: u64,
        new_digest_hash: vector<u8>,
        new_media_batch_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&conv.messages, seq), E_NO_MSG);

        let msg = table::borrow_mut(&mut conv.messages, seq);
        assert!(msg.sender == sender, E_FORBIDDEN);

        msg.digest_hash = new_digest_hash;
        msg.media_batch_hash = new_media_batch_hash;
        msg.edit_seq = msg.edit_seq + 1;

        event::emit(MessageEdited {
            conv: object::uid_to_address(&conv.id),
            seq,
            edit_seq: msg.edit_seq,
        });
    }

    /// Tombstone (soft-delete) a message (sender, mod, or admin)
    public entry fun tombstone_message(
        conv: &mut Conversation,
        seq: u64,
        reason: u8,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&conv.messages, seq), E_NO_MSG);

        let msg = table::borrow(&conv.messages, seq);
        let is_owner = msg.sender == sender;
        let is_mod_or_admin = table::contains(&conv.roles, sender) &&
            *table::borrow(&conv.roles, sender) >= ROLE_MOD;

        assert!(is_owner || is_mod_or_admin, E_FORBIDDEN);

        // Mark as tombstoned (set digest to empty)
        let msg_mut = table::borrow_mut(&mut conv.messages, seq);
        msg_mut.digest_hash = vector::empty();
        msg_mut.media_batch_hash = vector::empty();
        msg_mut.flags = msg_mut.flags | 1; // Set tombstone flag

        event::emit(MessageTombstoned {
            conv: object::uid_to_address(&conv.id),
            seq,
            reason,
        });
    }

    // === Receipts Functions ===

    /// Acknowledge delivery up to a sequence number
    public entry fun ack_delivery(
        conv: &mut Conversation,
        upto: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&conv.members, sender), E_NOT_MEMBER);

        if (vec_map::contains(&conv.delivered, &sender)) {
            let (_key, current) = vec_map::remove(&mut conv.delivered, &sender);
            if (upto > current) {
                vec_map::insert(&mut conv.delivered, sender, upto);
            } else {
                vec_map::insert(&mut conv.delivered, sender, current);
            };
        } else {
            vec_map::insert(&mut conv.delivered, sender, upto);
        };

        event::emit(DeliveredAck {
            conv: object::uid_to_address(&conv.id),
            member: sender,
            upto,
        });
    }

    /// Acknowledge read up to a sequence number
    public entry fun ack_read(
        conv: &mut Conversation,
        upto: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&conv.members, sender), E_NOT_MEMBER);

        if (vec_map::contains(&conv.read, &sender)) {
            let (_key, current) = vec_map::remove(&mut conv.read, &sender);
            if (upto > current) {
                vec_map::insert(&mut conv.read, sender, upto);
            } else {
                vec_map::insert(&mut conv.read, sender, current);
            };
        } else {
            vec_map::insert(&mut conv.read, sender, upto);
        };

        event::emit(ReadAck {
            conv: object::uid_to_address(&conv.id),
            member: sender,
            upto,
        });
    }

    // === Reactions & Pins Functions ===

    /// Add or remove a reaction to a message
    public entry fun react(
        conv: &mut Conversation,
        seq: u64,
        emoji_code: u32,
        add: bool,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&conv.members, sender), E_NOT_MEMBER);
        assert!(table::contains(&conv.messages, seq), E_NO_MSG);

        // Initialize reaction table for this message if needed
        if (!table::contains(&conv.reactions, seq)) {
            table::add(&mut conv.reactions, seq, table::new(ctx));
        };

        let msg_reactions = table::borrow_mut(&mut conv.reactions, seq);

        if (add) {
            // Add reaction
            if (table::contains(msg_reactions, emoji_code)) {
                let count = table::borrow_mut(msg_reactions, emoji_code);
                *count = *count + 1;
            } else {
                table::add(msg_reactions, emoji_code, 1);
            };
        } else {
            // Remove reaction
            if (table::contains(msg_reactions, emoji_code)) {
                let count = table::borrow_mut(msg_reactions, emoji_code);
                if (*count > 1) {
                    *count = *count - 1;
                } else {
                    table::remove(msg_reactions, emoji_code);
                };
            };
        };

        event::emit(Reacted {
            conv: object::uid_to_address(&conv.id),
            seq,
            member: sender,
            code: emoji_code,
            op: if (add) 1 else 0,
        });
    }

    /// Pin a message (mod/admin only)
    public entry fun pin(
        conv: &mut Conversation,
        seq: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_role_at_least(conv, sender, ROLE_MOD);
        assert!(table::contains(&conv.messages, seq), E_NO_MSG);

        if (!table::contains(&conv.pins, seq)) {
            table::add(&mut conv.pins, seq, true);
        };

        event::emit(Pinned {
            conv: object::uid_to_address(&conv.id),
            seq,
            on: true,
        });
    }

    /// Unpin a message (mod/admin only)
    public entry fun unpin(
        conv: &mut Conversation,
        seq: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_role_at_least(conv, sender, ROLE_MOD);

        if (table::contains(&conv.pins, seq)) {
            table::remove(&mut conv.pins, seq);
        };

        event::emit(Pinned {
            conv: object::uid_to_address(&conv.id),
            seq,
            on: false,
        });
    }

    // === Keys / Encryption Functions ===

    /// Rotate conversation encryption key (admin only)
    public entry fun rotate_conv_key(
        conv: &mut Conversation,
        _new_key_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_role_at_least(conv, sender, ROLE_ADMIN);

        // Increment version (stored in flags upper bits)
        let version = ((conv.flags >> 32) + 1) as u32;
        conv.flags = (conv.flags & 0xFFFFFFFF) | ((version as u64) << 32);

        event::emit(KeyRotated {
            conv: object::uid_to_address(&conv.id),
            version,
        });
    }

    /// Submit member-specific key bundle (member only)
    public entry fun submit_member_key(
        conv: &mut Conversation,
        _key_bundle_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&conv.members, sender), E_NOT_MEMBER);

        event::emit(MemberKeySubmitted {
            conv: object::uid_to_address(&conv.id),
            member: sender,
        });
    }

    // === Moderation / Limits Functions ===

    /// Moderator removes a message
    public entry fun mod_remove(
        conv: &mut Conversation,
        seq: u64,
        reason: u8,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_role_at_least(conv, sender, ROLE_MOD);
        assert!(table::contains(&conv.messages, seq), E_NO_MSG);

        // Tombstone the message
        let msg = table::borrow_mut(&mut conv.messages, seq);
        msg.digest_hash = vector::empty();
        msg.media_batch_hash = vector::empty();
        msg.flags = msg.flags | 1; // Set tombstone flag

        event::emit(Moderation {
            conv: object::uid_to_address(&conv.id),
            seq,
            reason,
        });
    }

    /// Set rate limits for a conversation (admin/mod only)
    /// 0 values inherit from Registry defaults
    public entry fun set_rate_limits(
        conv: &mut Conversation,
        window_secs: u64,
        per_user: u32,
        per_conv: u32,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_role_at_least(conv, sender, ROLE_MOD);

        conv.rl_window_secs = window_secs;
        conv.rl_per_user_per_window = per_user;
        conv.rl_per_conv_per_window = per_conv;

        event::emit(RateLimitsSet {
            conv: object::uid_to_address(&conv.id),
            window_secs,
            per_user,
            per_conv,
        });
    }

    // === Public Helper Functions ===

    /// Export a range of messages for pagination
    public fun export_range(
        conv: &Conversation,
        from_seq: u64,
        limit: u16
    ): vector<MessageDigest> {
        let mut result = vector::empty<MessageDigest>();
        let mut seq = from_seq;
        let end_seq = from_seq + (limit as u64);
        let max_seq = conv.next_seq;

        while (seq < end_seq && seq < max_seq) {
            if (table::contains(&conv.messages, seq)) {
                let msg = *table::borrow(&conv.messages, seq);
                vector::push_back(&mut result, msg);
            };
            seq = seq + 1;
        };

        result
    }

    /// Check if an address is a member
    public fun is_member(conv: &Conversation, who: address): bool {
        table::contains(&conv.members, who)
    }

    /// Get the next sequence number
    public fun next_seq(conv: &Conversation): u64 {
        conv.next_seq
    }

    /// Get conversation metadata hash
    public fun meta_hash(conv: &Conversation): vector<u8> {
        conv.meta_hash
    }

    /// Get member role (or ROLE_MEMBER if not found)
    public fun get_role(conv: &Conversation, who: address): u8 {
        if (table::contains(&conv.roles, who)) {
            *table::borrow(&conv.roles, who)
        } else {
            ROLE_MEMBER
        }
    }

    // === Internal Helper Functions ===

    /// Assert member has at least the specified role
    fun assert_role_at_least(conv: &Conversation, who: address, min_role: u8) {
        assert!(table::contains(&conv.roles, who), E_NOT_MEMBER);
        let role = *table::borrow(&conv.roles, who);
        assert!(role >= min_role, E_FORBIDDEN);
    }

    /// Enforce rate limits with tumbling window
    fun enforce_rate_limits(
        registry: &Registry,
        conv: &mut Conversation,
        sender: address,
        clock: &Clock
    ) {
        let now = clock::timestamp_ms(clock) / 1000; // Convert to seconds

        // Determine effective limits (0 = inherit from Registry)
        let window_secs = if (conv.rl_window_secs == 0) {
            registry.rl_window_secs
        } else {
            conv.rl_window_secs
        };

        let per_user_limit = if (conv.rl_per_user_per_window == 0) {
            registry.rl_per_user_per_window
        } else {
            conv.rl_per_user_per_window
        };

        let per_conv_limit = if (conv.rl_per_conv_per_window == 0) {
            registry.rl_per_conv_per_window
        } else {
            conv.rl_per_conv_per_window
        };

        // Check if we need to reset the window
        if (now - conv.rl_window_start >= window_secs) {
            // Reset window
            conv.rl_window_start = now;
            conv.rl_conv_count = 0;
            // Clear all user counts using tracked active users
            let mut i = 0;
            let len = vector::length(&conv.rl_active_users);
            while (i < len) {
                let user = *vector::borrow(&conv.rl_active_users, i);
                if (table::contains(&conv.rl_user_counts, user)) {
                    table::remove(&mut conv.rl_user_counts, user);
                };
                i = i + 1;
            };
            // Clear the active users list
            conv.rl_active_users = vector::empty();
        };

        // Check conversation limit
        assert!(conv.rl_conv_count + 1 <= per_conv_limit, E_RATE_LIMIT);

        // Check per-user limit
        let user_count = if (table::contains(&conv.rl_user_counts, sender)) {
            *table::borrow(&conv.rl_user_counts, sender)
        } else {
            0
        };
        assert!(user_count + 1 <= per_user_limit, E_RATE_LIMIT);

        // Increment counters
        conv.rl_conv_count = conv.rl_conv_count + 1;
        if (table::contains(&conv.rl_user_counts, sender)) {
            let count = table::borrow_mut(&mut conv.rl_user_counts, sender);
            *count = *count + 1;
        } else {
            table::add(&mut conv.rl_user_counts, sender, 1);
            // Track this user as active in the current window
            vector::push_back(&mut conv.rl_active_users, sender);
        };
    }

    // === Paid Messaging Functions ===

    /// Send a paid message to a profile owner
    public entry fun send_paid_message(
        registry: &Registry,
        conv: &mut Conversation,
        recipient_profile: &Profile,
        mut payment: Coin<MYS>,
        kind: u8,
        parent: u64,
        digest_hash: vector<u8>,
        media_batch_hash: vector<u8>,
        key_ref: vector<u8>,
        client_ts: u64,
        char_count: u32,
        dedupe_key: vector<u8>,
        nonce: u128,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!registry.paused, E_PAUSED);
        let sender = tx_context::sender(ctx);
        let recipient = profile::get_owner(recipient_profile);
        
        // Check if profile requires paid messaging
        assert!(profile::requires_paid_message(recipient_profile), E_NOT_PAID_MESSAGE);
        
        let min_cost = profile::get_min_message_cost(recipient_profile);
        assert!(option::is_some(&min_cost), E_NOT_PAID_MESSAGE);
        let required_amount = *option::borrow(&min_cost);
        
        // Check payment is sufficient
        assert!(coin::value(&payment) >= required_amount, E_INSUFFICIENT_PAYMENT);
        
        // Check dedupe
        assert!(!table::contains(&conv.used_dedupe, dedupe_key), E_DEDUPE_USED);
        table::add(&mut conv.used_dedupe, dedupe_key, true);

        // Check nonce
        if (!table::contains(&conv.nonces, sender)) {
            table::add(&mut conv.nonces, sender, table::new(ctx));
        };
        let member_nonces = table::borrow_mut(&mut conv.nonces, sender);
        assert!(!table::contains(member_nonces, nonce), E_NONCE_USED);
        table::add(member_nonces, nonce, true);

        // Enforce rate limits (paid messages also subject to rate limits)
        enforce_rate_limits(registry, conv, sender, clock);

        // Assign sequence number
        let seq = conv.next_seq;
        conv.next_seq = seq + 1;

        // Extract payment and hold in escrow
        let escrow_payment = coin::split(&mut payment, required_amount, ctx);
        let escrow_balance = coin::into_balance(escrow_payment);
        
        let current_epoch = tx_context::epoch(ctx);
        
        // Create escrow entry
        let escrow = PaidMessageEscrow {
            payer: sender,
            recipient,
            amount: required_amount,
            escrowed_balance: escrow_balance,
            created_epoch: current_epoch,
            claimed: false,
            parent_seq: seq,
        };
        
        table::add(&mut conv.paid_msg_escrow, seq, escrow);

        // Create message digest
        let msg = MessageDigest {
            seq,
            sender,
            kind,
            parent,
            digest_hash,
            media_batch_hash,
            key_ref,
            edit_seq: 0,
            client_ts,
            server_ts: clock::timestamp_ms(clock) / 1000,
            flags: 0,
            char_count: option::some(char_count),
            is_paid: true,
        };

        table::add(&mut conv.messages, seq, msg);

        // Emit events
        event::emit(MessageSent {
            conv: object::uid_to_address(&conv.id),
            seq,
            sender,
            kind,
        });

        event::emit(PaidMessageSent {
            conv: object::uid_to_address(&conv.id),
            seq,
            payer: sender,
            recipient,
            amount: required_amount,
            created_epoch: current_epoch,
        });

        // Return excess payment
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, sender);
        } else {
            coin::destroy_zero(payment);
        };
    }

    /// Reply to a paid message and trigger payment release if conditions are met
    public entry fun reply_to_paid_message(
        registry: &Registry,
        conv: &mut Conversation,
        platform: &mut Platform,
        spt_config: &SocialProofTokensConfig,
        paid_msg_seq: u64,
        kind: u8,
        digest_hash: vector<u8>,
        media_batch_hash: vector<u8>,
        key_ref: vector<u8>,
        client_ts: u64,
        char_count: u32,
        dedupe_key: vector<u8>,
        nonce: u128,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!registry.paused, E_PAUSED);
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&conv.members, sender), E_NOT_MEMBER);

        // Verify the paid message exists and has escrow
        assert!(table::contains(&conv.paid_msg_escrow, paid_msg_seq), E_NOT_PAID_MESSAGE);
        let escrow = table::borrow(&conv.paid_msg_escrow, paid_msg_seq);
        
        // Verify sender is the recipient
        assert!(sender == escrow.recipient, E_FORBIDDEN);
        
        // Verify payment not already claimed
        assert!(!escrow.claimed, E_PAYMENT_ALREADY_CLAIMED);
        
        // Verify payment not expired
        let current_epoch = tx_context::epoch(ctx);
        assert!(current_epoch - escrow.created_epoch <= PAYMENT_EXPIRATION_EPOCHS, E_PAYMENT_EXPIRED);

        // Check dedupe
        assert!(!table::contains(&conv.used_dedupe, dedupe_key), E_DEDUPE_USED);
        table::add(&mut conv.used_dedupe, dedupe_key, true);

        // Check nonce
        if (!table::contains(&conv.nonces, sender)) {
            table::add(&mut conv.nonces, sender, table::new(ctx));
        };
        let member_nonces = table::borrow_mut(&mut conv.nonces, sender);
        assert!(!table::contains(member_nonces, nonce), E_NONCE_USED);
        table::add(member_nonces, nonce, true);

        // Verify reply meets minimum character requirement
        assert!(char_count >= MIN_REPLY_CHARS, E_REPLY_TOO_SHORT);

        // Assign sequence number for reply
        let seq = conv.next_seq;
        conv.next_seq = seq + 1;

        // Create reply message digest
        let msg = MessageDigest {
            seq,
            sender,
            kind,
            parent: paid_msg_seq, // Link to paid message
            digest_hash,
            media_batch_hash,
            key_ref,
            edit_seq: 0,
            client_ts,
            server_ts: clock::timestamp_ms(clock) / 1000,
            flags: 0,
            char_count: option::some(char_count),
            is_paid: false,
        };

        table::add(&mut conv.messages, seq, msg);

        event::emit(MessageSent {
            conv: object::uid_to_address(&conv.id),
            seq,
            sender,
            kind,
        });

        event::emit(PaidMessageReplied {
            conv: object::uid_to_address(&conv.id),
            paid_msg_seq,
            reply_seq: seq,
            recipient: sender,
            reply_char_count: char_count,
        });

        // Automatically claim the payment
        claim_payment_internal(conv, platform, spt_config, paid_msg_seq, ctx);
    }

    /// Claim payment from a replied paid message (internal helper)
    fun claim_payment_internal(
        conv: &mut Conversation,
        platform: &mut Platform,
        spt_config: &SocialProofTokensConfig,
        paid_msg_seq: u64,
        ctx: &mut TxContext
    ) {
        // Get mutable escrow
        let escrow = table::borrow_mut(&mut conv.paid_msg_escrow, paid_msg_seq);
        assert!(!escrow.claimed, E_PAYMENT_ALREADY_CLAIMED);

        let total_amount = escrow.amount;
        
        // Calculate fees
        let platform_fee = (total_amount * PAID_MSG_PLATFORM_FEE_BPS) / 10000;
        let treasury_fee = (total_amount * PAID_MSG_TREASURY_FEE_BPS) / 10000;
        let net_amount = total_amount - platform_fee - treasury_fee;

        // Split and distribute payments
        let mut escrow_coin = coin::from_balance(balance::withdraw_all(&mut escrow.escrowed_balance), ctx);

        // Platform fee
        if (platform_fee > 0) {
            let mut platform_fee_coin = coin::split(&mut escrow_coin, platform_fee, ctx);
            platform::add_to_treasury(platform, &mut platform_fee_coin, platform_fee, ctx);
            coin::destroy_zero(platform_fee_coin);
        };

        // Treasury fee
        if (treasury_fee > 0) {
            let treasury_fee_coin = coin::split(&mut escrow_coin, treasury_fee, ctx);
            transfer::public_transfer(treasury_fee_coin, spt::get_ecosystem_treasury(spt_config));
        };

        // Net amount to recipient
        transfer::public_transfer(escrow_coin, escrow.recipient);

        // Mark as claimed
        escrow.claimed = true;

        let current_epoch = tx_context::epoch(ctx);

        event::emit(PaymentClaimed {
            conv: object::uid_to_address(&conv.id),
            seq: paid_msg_seq,
            recipient: escrow.recipient,
            amount: total_amount,
            platform_fee,
            treasury_fee,
            net_amount,
            claimed_epoch: current_epoch,
        });
    }

    /// Refund an expired or unclaimed paid message payment
    public entry fun refund_paid_message(
        conv: &mut Conversation,
        paid_msg_seq: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Verify escrow exists
        assert!(table::contains(&conv.paid_msg_escrow, paid_msg_seq), E_NOT_PAID_MESSAGE);
        
        let escrow = table::borrow_mut(&mut conv.paid_msg_escrow, paid_msg_seq);
        
        // Only payer can request refund
        assert!(sender == escrow.payer, E_FORBIDDEN);
        
        // Verify not already claimed
        assert!(!escrow.claimed, E_PAYMENT_ALREADY_CLAIMED);

        // Verify payment is expired (>= to include the expiration epoch)
        let current_epoch = tx_context::epoch(ctx);
        assert!(current_epoch - escrow.created_epoch >= PAYMENT_EXPIRATION_EPOCHS, E_PAYMENT_EXPIRED);

        let refund_amount = escrow.amount;
        
        // Refund the payment
        let refund_coin = coin::from_balance(balance::withdraw_all(&mut escrow.escrowed_balance), ctx);
        transfer::public_transfer(refund_coin, escrow.payer);

        // Mark as claimed (to prevent double refund)
        escrow.claimed = true;

        event::emit(PaymentRefunded {
            conv: object::uid_to_address(&conv.id),
            seq: paid_msg_seq,
            payer: escrow.payer,
            amount: refund_amount,
            refunded_epoch: current_epoch,
            reason: 0, // 0 = expired
        });
    }

    // === Test-only Functions ===

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        bootstrap_init(ctx);
    }
}

