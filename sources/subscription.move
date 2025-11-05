// Copyright (c) The Social Proof Foundation, LLC.
// SPDX-License-Identifier: Apache-2.0

/// Subscription module for the MySocial network
/// Handles subscription services for profiles & MyData

#[allow(duplicate_alias)]
module social_contracts::subscription {
    use mys::{
        object::{Self, UID, ID},
        tx_context::{Self, TxContext},
        transfer,
        clock::{Self, Clock},
        coin::{Self, Coin},
        balance::{Self, Balance},
        event
    };
    use mys::mys::MYS;
    
    /// Error codes
    const EInvalidFee: u64 = 12;
    const ENoAccess: u64 = 77;
    const ESubscriptionExpired: u64 = 78;
    const EAutoRenewalDisabled: u64 = 79;
    const ENotSubscriptionOwner: u64 = 80;

    /// Profile subscription service - one per profile
    public struct ProfileSubscriptionService has key {
        id: UID,
        /// Profile owner who receives subscription fees
        profile_owner: address,
        /// Monthly subscription fee in MYS
        monthly_fee: u64,
        /// Whether this service allows new subscriptions
        active: bool,
        /// Total number of active subscribers
        subscriber_count: u64,
        /// Version for upgrades
        version: u64,
    }

    /// Individual subscription to a profile
    public struct ProfileSubscription has key {
        id: UID,
        /// The profile service this subscription is for
        service_id: ID,
        /// Subscriber's address
        subscriber: address,
        /// When the subscription was created
        created_at: u64,
        /// When the subscription expires (timestamp in ms)
        expires_at: u64,
        /// Whether auto-renewal is enabled
        auto_renew: bool,
        /// Balance for auto-renewal payments
        renewal_balance: Balance<MYS>,
        /// Number of times this subscription has been renewed
        renewal_count: u64,
    }

    /// Events
    public struct ProfileSubscriptionCreatedEvent has copy, drop {
        service_id: ID,
        subscriber: address,
        expires_at: u64,
        monthly_fee: u64,
        auto_renew: bool,
    }

    public struct ProfileSubscriptionRenewedEvent has copy, drop {
        subscription_id: ID,
        subscriber: address,
        new_expires_at: u64,
        renewal_count: u64,
        auto_renewed: bool,
    }

    public struct ProfileSubscriptionCancelledEvent has copy, drop {
        subscription_id: ID,
        subscriber: address,
        refunded_amount: u64,
    }

    /// Additional event for fee updates
    public struct ProfileSubscriptionUpdatedEvent has copy, drop {
        service_id: ID,
        old_fee: u64,
        new_fee: u64,
        updated_by: address,
    }

    /// Create a subscription service for a profile (called by profile owner)
    public fun create_profile_service(
        profile_owner: address,
        monthly_fee: u64,
        ctx: &mut TxContext
    ): ProfileSubscriptionService {
        ProfileSubscriptionService {
            id: object::new(ctx),
            profile_owner,
            monthly_fee,
            active: true,
            subscriber_count: 0,
            version: 1,
        }
    }

    /// Entry function to create and share a profile subscription service
    public entry fun create_profile_service_entry(
        monthly_fee: u64,
        ctx: &mut TxContext
    ) {
        let service = create_profile_service(
            tx_context::sender(ctx),
            monthly_fee,
            ctx
        );
        transfer::share_object(service);
    }

    /// Subscribe to a profile with optional auto-renewal
    public entry fun subscribe_to_profile(
        service: &mut ProfileSubscriptionService,
        payment: &mut Coin<MYS>,
        auto_renew: bool,
        renewal_months: u64, // How many months to fund for auto-renewal (0 if not auto-renewing)
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(service.active, ENoAccess);
        let subscriber = tx_context::sender(ctx);
        let now = clock::timestamp_ms(clock);
        
        // Calculate required payment (1 month + renewal months if auto-renew)
        let months_to_pay = if (auto_renew) { 1 + renewal_months } else { 1 };
        let total_required = service.monthly_fee * months_to_pay;
        assert!(coin::value(payment) >= total_required, EInvalidFee);

        // Take payment for first month
        let first_month_payment = coin::split(payment, service.monthly_fee, ctx);
        transfer::public_transfer(first_month_payment, service.profile_owner);

        // Take renewal payment if auto-renew enabled
        let renewal_balance = if (auto_renew && renewal_months > 0) {
            let renewal_payment = coin::split(payment, service.monthly_fee * renewal_months, ctx);
            coin::into_balance(renewal_payment)
        } else {
            balance::zero<MYS>()
        };

        // Calculate expiration (30 days from now)
        let expires_at = now + (30 * 24 * 60 * 60 * 1000); // 30 days in milliseconds

        let subscription = ProfileSubscription {
            id: object::new(ctx),
            service_id: object::id(service),
            subscriber,
            created_at: now,
            expires_at,
            auto_renew,
            renewal_balance,
            renewal_count: 0,
        };

        service.subscriber_count = service.subscriber_count + 1;

        event::emit(ProfileSubscriptionCreatedEvent {
            service_id: object::id(service),
            subscriber,
            expires_at,
            monthly_fee: service.monthly_fee,
            auto_renew,
        });

        transfer::transfer(subscription, subscriber);
    }

    /// Manually renew a subscription
    public entry fun renew_subscription(
        service: &ProfileSubscriptionService,
        subscription: &mut ProfileSubscription,
        payment: Coin<MYS>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let subscriber = tx_context::sender(ctx);
        assert!(subscription.subscriber == subscriber, ENotSubscriptionOwner);
        assert!(subscription.service_id == object::id(service), ENoAccess);
        assert!(coin::value(&payment) >= service.monthly_fee, EInvalidFee);

        transfer::public_transfer(payment, service.profile_owner);

        // Extend expiration by 30 days
        let now = clock::timestamp_ms(clock);
        let extension = 30 * 24 * 60 * 60 * 1000; // 30 days in milliseconds
        
        // If subscription is expired, start from now, otherwise extend current expiration
        subscription.expires_at = if (now > subscription.expires_at) {
            now + extension
        } else {
            subscription.expires_at + extension
        };
        
        subscription.renewal_count = subscription.renewal_count + 1;

        event::emit(ProfileSubscriptionRenewedEvent {
            subscription_id: object::id(subscription),
            subscriber,
            new_expires_at: subscription.expires_at,
            renewal_count: subscription.renewal_count,
            auto_renewed: false,
        });
    }

    /// Gas-optimized auto-renew using pre-funded renewal balance
    /// Now includes protection against fee changes and service deactivation
    public entry fun auto_renew_subscription(
        service: &ProfileSubscriptionService,
        subscription: &mut ProfileSubscription,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(subscription.service_id == object::id(service), ENoAccess);
        assert!(subscription.auto_renew, EAutoRenewalDisabled);
        
        // Check that the service is still active
        assert!(service.active, ENoAccess);
        
        let now = clock::timestamp_ms(clock);
        
        // Only allow auto-renewal if subscription has actually expired
        assert!(subscription.expires_at <= now, ESubscriptionExpired);
        
        // Check if there's enough balance for renewal at current fee
        let renewal_balance_value = balance::value(&subscription.renewal_balance);
        
        // Protection: If fee increased beyond what user has in renewal balance, cancel auto-renewal
        if (renewal_balance_value < service.monthly_fee) {
            subscription.auto_renew = false;
            // Emit event indicating auto-renewal was cancelled due to insufficient funds/fee increase
            event::emit(ProfileSubscriptionCancelledEvent {
                subscription_id: object::id(subscription),
                subscriber: subscription.subscriber,
                refunded_amount: 0, // No refund in this case
            });
            return
        };

        // Use renewal balance (gas optimized - avoid intermediate coin creation when possible)
        let renewal_payment = coin::from_balance(
            balance::split(&mut subscription.renewal_balance, service.monthly_fee),
            ctx
        );
        transfer::public_transfer(renewal_payment, service.profile_owner);
        
        // Pre-calculate extension to avoid repeated calculations
        let extension = 2_592_000_000; // 30 days in milliseconds (pre-calculated)
        subscription.expires_at = now + extension;
        subscription.renewal_count = subscription.renewal_count + 1;

        event::emit(ProfileSubscriptionRenewedEvent {
            subscription_id: object::id(subscription),
            subscriber: subscription.subscriber,
            new_expires_at: subscription.expires_at,
            renewal_count: subscription.renewal_count,
            auto_renewed: true,
        });
    }

    /// Check if subscription is eligible for auto-renewal without expensive operations
    /// Now includes service activation check
    public fun can_auto_renew(
        subscription: &ProfileSubscription,
        service: &ProfileSubscriptionService,
        clock: &Clock
    ): bool {
        if (!subscription.auto_renew) return false;
        if (subscription.service_id != object::id(service)) return false;
        if (!service.active) return false; // Check service is active
        
        let now = clock::timestamp_ms(clock);
        if (subscription.expires_at > now) return false;
        
        balance::value(&subscription.renewal_balance) >= service.monthly_fee
    }

    /// User funds their renewal balance for auto-renewal
    public entry fun fund_renewal_balance(
        subscription: &mut ProfileSubscription,
        payment: Coin<MYS>,
        ctx: &mut TxContext,
    ) {
        let subscriber = tx_context::sender(ctx);
        assert!(subscription.subscriber == subscriber, ENotSubscriptionOwner);
        
        balance::join(&mut subscription.renewal_balance, coin::into_balance(payment));
    }

    /// Check if a subscription is valid for access
    public fun is_subscription_valid(
        subscription: &ProfileSubscription,
        service: &ProfileSubscriptionService,
        clock: &Clock,
    ): bool {
        if (object::id(service) != subscription.service_id) {
            return false
        };
        
        let now = clock::timestamp_ms(clock);
        subscription.expires_at > now
    }

    /// MyData integration for encrypted content access
    public entry fun seal_approve(
        _id: vector<u8>,
        subscription: &ProfileSubscription,
        service: &ProfileSubscriptionService,
        clock: &Clock,
    ) {
        assert!(is_subscription_valid(subscription, service, clock), ENoAccess);
    }

    /// Update service fee (profile owner only)
    /// Now emits event when fee changes
    public entry fun update_service_fee(
        service: &mut ProfileSubscriptionService,
        new_fee: u64,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::sender(ctx) == service.profile_owner, ENotSubscriptionOwner);
        let old_fee = service.monthly_fee;
        service.monthly_fee = new_fee;
        
        // Emit event about fee change
        event::emit(ProfileSubscriptionUpdatedEvent {
            service_id: object::id(service),
            old_fee,
            new_fee,
            updated_by: tx_context::sender(ctx),
        });
    }

    /// Deactivate service (profile owner only)
    public entry fun deactivate_service(
        service: &mut ProfileSubscriptionService,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::sender(ctx) == service.profile_owner, ENotSubscriptionOwner);
        service.active = false;
    }

    /// Cancel subscription and get refund of unused renewal balance
    public entry fun cancel_subscription(
        service: &mut ProfileSubscriptionService,
        mut subscription: ProfileSubscription,
        ctx: &mut TxContext,
    ) {
        let subscriber = tx_context::sender(ctx);
        assert!(subscription.subscriber == subscriber, ENotSubscriptionOwner);
        assert!(subscription.service_id == object::id(service), ENoAccess);

        // Refund any remaining renewal balance
        let refund_amount = balance::value(&subscription.renewal_balance);
        if (refund_amount > 0) {
            let refund = coin::from_balance(
                balance::withdraw_all(&mut subscription.renewal_balance),
                ctx
            );
            transfer::public_transfer(refund, subscriber);
        };

        service.subscriber_count = service.subscriber_count - 1;

        event::emit(ProfileSubscriptionCancelledEvent {
            subscription_id: object::id(&subscription),
            subscriber,
            refunded_amount: refund_amount,
        });

        // Destroy the subscription
        let ProfileSubscription {
            id,
            service_id: _,
            subscriber: _,
            created_at: _,
            expires_at: _,
            auto_renew: _,
            renewal_balance,
            renewal_count: _,
        } = subscription;

        balance::destroy_zero(renewal_balance);
        object::delete(id);
    }

    // === Read-only functions ===

    public fun service_monthly_fee(service: &ProfileSubscriptionService): u64 {
        service.monthly_fee
    }

    public fun service_subscriber_count(service: &ProfileSubscriptionService): u64 {
        service.subscriber_count
    }

    public fun subscription_expires_at(subscription: &ProfileSubscription): u64 {
        subscription.expires_at
    }

    public fun subscription_auto_renew(subscription: &ProfileSubscription): bool {
        subscription.auto_renew
    }

    public fun subscription_renewal_balance(subscription: &ProfileSubscription): u64 {
        balance::value(&subscription.renewal_balance)
    }

    #[test_only]
    public fun destroy_for_testing(service: ProfileSubscriptionService, subscription: ProfileSubscription) {
        let ProfileSubscriptionService { id, .. } = service;
        object::delete(id);
        let ProfileSubscription { id, renewal_balance, .. } = subscription;
        balance::destroy_zero(renewal_balance);
        object::delete(id);
    }
}
