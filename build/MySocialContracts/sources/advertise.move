module social_contracts::advertise {
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    
    use mys::object::{Self, UID};
    use mys::tx_context::{Self, TxContext};
    use mys::event;
    use mys::transfer;
    use mys::table::{Self, Table};
    use mys::coin::{Self, Coin};
    use mys::balance::{Self, Balance};
    use mys::mys::MYS;
    use mys::clock::{Self, Clock};
    use mys::url::{Self, Url};
    use social_contracts::profile::{Self, Profile};
    use social_contracts::post::{Self, Post};
    use mys::display;
    
    /// Error codes
    const EUnauthorized: u64 = 0;
    const EInvalidDuration: u64 = 1;
    const EInvalidTarget: u64 = 2;
    const EInvalidBudget: u64 = 3;
    const EInsufficientPayment: u64 = 4;
    const ECampaignInactive: u64 = 5;
    const ECampaignActive: u64 = 6;
    const EInvalidRefund: u64 = 7;
    const ECampaignExpired: u64 = 8;
    const EInvalidBid: u64 = 9;
    const EInvalidAudience: u64 = 10;
    
    /// Campaign status
    const CAMPAIGN_STATUS_DRAFT: u8 = 0;
    const CAMPAIGN_STATUS_ACTIVE: u8 = 1;
    const CAMPAIGN_STATUS_PAUSED: u8 = 2;
    const CAMPAIGN_STATUS_COMPLETED: u8 = 3;
    const CAMPAIGN_STATUS_CANCELED: u8 = 4;
    
    /// Ad format types
    const AD_FORMAT_FEED: u8 = 0;       // Regular post in feed
    const AD_FORMAT_STORY: u8 = 1;      // Story format ad
    const AD_FORMAT_FEATURED: u8 = 2;   // Featured post (premium placement)
    const AD_FORMAT_BANNER: u8 = 3;     // Banner ad
    
    /// Ad objective types
    const AD_OBJECTIVE_ENGAGEMENT: u8 = 0;  // Likes, comments, shares
    const AD_OBJECTIVE_REACH: u8 = 1;       // Maximize unique viewers
    const AD_OBJECTIVE_TRAFFIC: u8 = 2;     // Clicks to destination
    const AD_OBJECTIVE_CONVERSION: u8 = 3;  // Conversions/action completion
    
    /// Targeting criteria types
    const TARGET_LOCATION: u8 = 0;
    const TARGET_AGE: u8 = 1;
    const TARGET_GENDER: u8 = 2;
    const TARGET_INTERESTS: u8 = 3;
    const TARGET_FOLLOWERS: u8 = 4;
    const TARGET_CUSTOM: u8 = 5;
    
    /// Engagement action types
    const ENGAGEMENT_VIEW: u8 = 0;       // Ad was viewed
    const ENGAGEMENT_CLICK: u8 = 1;      // Ad was clicked
    const ENGAGEMENT_INTERACTION: u8 = 2; // User interacted with ad content
    const ENGAGEMENT_CONVERSION: u8 = 3;  // Conversion action completed
    
    /// Bidding models
    const BID_MODEL_CPM: u8 = 0;   // Cost per mille (thousand impressions)
    const BID_MODEL_CPC: u8 = 1;   // Cost per click
    const BID_MODEL_CPE: u8 = 2;   // Cost per engagement 
    const BID_MODEL_CPA: u8 = 3;   // Cost per action/acquisition
    
    /// Platform fee percentage in basis points (100 = 1%)
    const PLATFORM_FEE_BPS: u64 = 1000; // 10%
    
    /// Base costs for different ad formats (in MYS tokens)
    const BASE_COST_FEED: u64 = 100000000;     // 100 MYS
    const BASE_COST_STORY: u64 = 200000000;    // 200 MYS
    const BASE_COST_FEATURED: u64 = 500000000; // 500 MYS
    const BASE_COST_BANNER: u64 = 300000000;   // 300 MYS
    
    /// Minimum campaign duration in seconds
    const MIN_CAMPAIGN_DURATION: u64 = 86400; // 1 day
    
    /// Audience targeting criteria
    public struct TargetingCriteria has store, drop, copy {
        /// Type of targeting
        targeting_type: u8,
        /// Value for this targeting rule
        value: String,
    }
    
    /// Ad creative content
    public struct AdCreative has store, drop {
        /// Title of the ad
        title: String,
        /// Main content text
        content: String,
        /// Optional media URL
        media_url: Option<Url>,
        /// Call to action text
        cta_text: String,
        /// Destination URL
        destination_url: Option<Url>,
    }
    
    /// Advertiser profile
    public struct Advertiser has key {
        id: UID,
        /// Advertiser's profile ID
        profile_id: address,
        /// Total spent across all campaigns
        total_spent: u64,
        /// Number of campaigns created
        campaign_count: u64,
        /// Timestamp when advertiser was created
        created_at: u64,
        /// Additional verification or approval status
        verified: bool,
    }
    
    /// Ad campaign
    public struct Campaign has key {
        id: UID,
        /// Advertiser who created this campaign
        advertiser: address,
        /// Campaign name
        name: String,
        /// Linked post that serves as ad content
        post_id: Option<address>,
        /// Ad format type
        format: u8,
        /// Ad objective
        objective: u8,
        /// Start timestamp
        start_time: u64,
        /// End timestamp
        end_time: u64,
        /// Total budget in MYS tokens
        total_budget: u64,
        /// Remaining budget
        remaining_budget: u64,
        /// Balance of MYS tokens
        budget_balance: Balance<MYS>,
        /// Bid amount per engagement (depends on bid model)
        bid_amount: u64,
        /// Bidding model type
        bid_model: u8,
        /// Ad targeting criteria
        targeting: vector<TargetingCriteria>,
        /// Custom audience targeting (optional)
        custom_audience: vector<address>,
        /// Ad creative content
        creative: AdCreative,
        /// Campaign status
        status: u8,
        /// Number of impressions
        impressions: u64,
        /// Number of clicks
        clicks: u64,
        /// Number of other engagements
        engagements: u64,
        /// Number of conversions
        conversions: u64,
        /// Creation timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Engagement record for tracking ad interactions
    public struct Engagement has key {
        id: UID,
        /// Campaign ID
        campaign_id: address,
        /// User who engaged
        user: address,
        /// Engagement type
        engagement_type: u8,
        /// Timestamp
        timestamp: u64,
        /// Cost of this engagement
        cost: u64,
    }
    
    /// Ad registry to track all campaigns and advertisers
    public struct AdRegistry has key {
        id: UID,
        /// Table of advertisers by address
        advertisers: Table<address, address>,
        /// Table of campaigns by ID
        campaigns: Table<address, address>,
        /// Table of campaigns by advertiser
        advertiser_campaigns: Table<address, vector<address>>,
        /// Table of campaigns by post ID
        post_campaigns: Table<address, address>,
        /// Total MYS tokens collected as platform fees
        platform_fees: Balance<MYS>,
        /// Admin address
        admin: address,
    }
    
    /// Cap for administrative control
    public struct AdAdminCap has key, store {
        id: UID,
    }
    
    // === Events ===
    
    /// Event emitted when a new advertiser is registered
    public struct AdvertiserRegisteredEvent has copy, drop {
        advertiser_id: address,
        profile_id: address,
        created_at: u64,
    }
    
    /// Event emitted when a new campaign is created
    public struct CampaignCreatedEvent has copy, drop {
        campaign_id: address,
        advertiser: address,
        name: String,
        post_id: Option<address>,
        format: u8,
        objective: u8,
        start_time: u64,
        end_time: u64,
        total_budget: u64,
        bid_amount: u64,
        bid_model: u8,
        created_at: u64,
    }
    
    /// Event emitted when a campaign is updated
    public struct CampaignUpdatedEvent has copy, drop {
        campaign_id: address,
        advertiser: address,
        status: u8,
        updated_at: u64,
    }
    
    /// Event emitted when a campaign is funded
    public struct CampaignFundedEvent has copy, drop {
        campaign_id: address,
        advertiser: address,
        amount: u64,
        timestamp: u64,
    }
    
    /// Event emitted when a user engages with an ad
    public struct AdEngagementEvent has copy, drop {
        campaign_id: address,
        user: address,
        engagement_type: u8,
        cost: u64,
        timestamp: u64,
    }
    
    /// Event emitted when platform fees are withdrawn
    public struct PlatformFeesWithdrawnEvent has copy, drop {
        amount: u64,
        recipient: address,
        timestamp: u64,
    }
    
    // === Module Initialization ===
    
    #[allow(lint(self_transfer))]
    /// Initialize the ad registry
    fun init_module(ctx: &mut TxContext) {
        let registry = AdRegistry {
            id: object::new(ctx),
            advertisers: table::new(ctx),
            campaigns: table::new(ctx),
            advertiser_campaigns: table::new(ctx),
            post_campaigns: table::new(ctx),
            platform_fees: balance::zero(),
            admin: tx_context::sender(ctx),
        };
        
        // Create admin capability
        let admin_cap = AdAdminCap {
            id: object::new(ctx),
        };
        
        // Share the registry as a shared object
        transfer::share_object(registry);
        
        // Transfer admin cap to sender
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }
    
    // === Advertiser Functions ===
    
    /// Register a new advertiser profile
    public entry fun register_advertiser(
        registry: &mut AdRegistry,
        profile: &Profile,
        ctx: &mut TxContext
    ) {
        // Verify caller owns the profile
        assert!(profile::owner(profile) == tx_context::sender(ctx), EUnauthorized);
        
        // Get the profile ID
        let profile_id = object::uid_to_address(profile::id(profile));
        
        // Create a new advertiser
        let advertiser = Advertiser {
            id: object::new(ctx),
            profile_id,
            total_spent: 0,
            campaign_count: 0,
            created_at: tx_context::epoch(ctx),
            verified: false,
        };
        
        let advertiser_id = object::uid_to_address(&advertiser.id);
        
        // Add to registry
        table::add(&mut registry.advertisers, tx_context::sender(ctx), advertiser_id);
        table::add(&mut registry.advertiser_campaigns, advertiser_id, vector::empty<address>());
        
        // Share advertiser object
        transfer::share_object(advertiser);
        
        // Emit registration event
        event::emit(AdvertiserRegisteredEvent {
            advertiser_id,
            profile_id,
            created_at: tx_context::epoch(ctx),
        });
    }
    
    /// Create a new ad campaign
    public entry fun create_campaign(
        registry: &mut AdRegistry,
        advertiser: &mut Advertiser,
        name: String,
        post: &Post,
        format: u8,
        objective: u8,
        start_time: u64,
        duration: u64,
        total_budget: u64,
        bid_amount: u64,
        bid_model: u8,
        targeting_types: vector<u8>,
        targeting_values: vector<String>,
        payment: &mut Coin<MYS>,
        title: String,
        content: String,
        media_url: vector<u8>,
        cta_text: String,
        destination_url: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Verify caller is the advertiser owner
        assert!(tx_context::sender(ctx) == advertiser.profile_id, EUnauthorized);
        
        // Verify minimum campaign duration
        assert!(duration >= MIN_CAMPAIGN_DURATION, EInvalidDuration);
        
        // Verify valid bid model
        assert!(
            bid_model == BID_MODEL_CPM || 
            bid_model == BID_MODEL_CPC || 
            bid_model == BID_MODEL_CPE ||
            bid_model == BID_MODEL_CPA,
            EInvalidBid
        );
        
        // Verify valid ad format
        assert!(
            format == AD_FORMAT_FEED || 
            format == AD_FORMAT_STORY || 
            format == AD_FORMAT_FEATURED ||
            format == AD_FORMAT_BANNER,
            EInvalidTarget
        );
        
        // Verify total budget meets minimum for format
        let minimum_budget = get_minimum_budget_for_format(format);
        assert!(total_budget >= minimum_budget, EInvalidBudget);
        
        // Verify payment
        assert!(coin::value(payment) >= total_budget, EInsufficientPayment);
        
        // Calculate end time
        let current_time = clock::timestamp_ms(clock) / 1000; // Convert to seconds
        let end_time = start_time + duration;
        
        // Calculate platform fee (10%)
        let platform_fee = (total_budget * PLATFORM_FEE_BPS) / 10000;
        let campaign_budget = total_budget - platform_fee;
        
        // Process payment
        let payment_coin = coin::split(payment, total_budget, ctx);
        let mut payment_balance = coin::into_balance(payment_coin);
        
        // Split platform fee and campaign budget
        let platform_fee_balance = balance::split(&mut payment_balance, platform_fee);
        
        // Build targeting criteria
        assert!(vector::length(&targeting_types) == vector::length(&targeting_values), EInvalidTarget);
        let targeting = build_targeting_criteria(targeting_types, targeting_values);
        
        // Build ad creative
        let creative = build_ad_creative(
            title,
            content,
            media_url,
            cta_text,
            destination_url,
            ctx
        );
        
        // Create campaign
        let mut campaign = Campaign {
            id: object::new(ctx),
            advertiser: object::uid_to_address(&advertiser.id),
            name,
            post_id: option::some(object::uid_to_address(post::id(post))),
            format,
            objective,
            start_time,
            end_time,
            total_budget: campaign_budget,
            remaining_budget: campaign_budget,
            budget_balance: payment_balance,
            bid_amount,
            bid_model,
            targeting,
            custom_audience: vector::empty(),
            creative,
            status: CAMPAIGN_STATUS_DRAFT,
            impressions: 0,
            clicks: 0,
            engagements: 0,
            conversions: 0,
            created_at: current_time,
            updated_at: current_time,
        };
        
        let campaign_id = object::uid_to_address(&campaign.id);
        
        // Update advertiser stats
        advertiser.campaign_count = advertiser.campaign_count + 1;
        
        // Add to registry
        table::add(&mut registry.campaigns, campaign_id, campaign_id);
        
        // Add to advertiser's campaigns
        let campaigns = table::borrow_mut(&mut registry.advertiser_campaigns, object::uid_to_address(&advertiser.id));
        vector::push_back(campaigns, campaign_id);
        
        // Add to post campaigns
        if (option::is_some(&campaign.post_id)) {
            let post_id = option::extract(&mut campaign.post_id);
            table::add(&mut registry.post_campaigns, post_id, campaign_id);
            option::fill(&mut campaign.post_id, post_id);
        };
        
        // Add platform fee to registry
        balance::join(&mut registry.platform_fees, platform_fee_balance);
        
        // Make a copy of campaign.post_id for the event
        let post_id_copy = campaign.post_id;
        
        // Share campaign object
        transfer::share_object(campaign);
        
        // Emit campaign created event
        event::emit(CampaignCreatedEvent {
            campaign_id,
            advertiser: object::uid_to_address(&advertiser.id),
            name: name,
            post_id: post_id_copy,
            format,
            objective,
            start_time,
            end_time,
            total_budget: campaign_budget,
            bid_amount,
            bid_model,
            created_at: current_time,
        });
    }
    
    /// Activate a campaign
    public entry fun activate_campaign(
        registry: &AdRegistry,
        advertiser: &Advertiser,
        campaign: &mut Campaign,
        ctx: &mut TxContext
    ) {
        // Verify caller is the advertiser owner
        assert!(tx_context::sender(ctx) == advertiser.profile_id, EUnauthorized);
        assert!(campaign.advertiser == object::uid_to_address(&advertiser.id), EUnauthorized);
        
        // Verify campaign can be activated
        assert!(campaign.status == CAMPAIGN_STATUS_DRAFT || campaign.status == CAMPAIGN_STATUS_PAUSED, ECampaignActive);
        
        // Update campaign status
        campaign.status = CAMPAIGN_STATUS_ACTIVE;
        campaign.updated_at = tx_context::epoch(ctx);
        
        // Emit campaign updated event
        event::emit(CampaignUpdatedEvent {
            campaign_id: object::uid_to_address(&campaign.id),
            advertiser: object::uid_to_address(&advertiser.id),
            status: campaign.status,
            updated_at: campaign.updated_at,
        });
    }
    
    /// Pause a campaign
    public entry fun pause_campaign(
        registry: &AdRegistry,
        advertiser: &Advertiser,
        campaign: &mut Campaign,
        ctx: &mut TxContext
    ) {
        // Verify caller is the advertiser owner
        assert!(tx_context::sender(ctx) == advertiser.profile_id, EUnauthorized);
        assert!(campaign.advertiser == object::uid_to_address(&advertiser.id), EUnauthorized);
        
        // Verify campaign is active
        assert!(campaign.status == CAMPAIGN_STATUS_ACTIVE, ECampaignInactive);
        
        // Update campaign status
        campaign.status = CAMPAIGN_STATUS_PAUSED;
        campaign.updated_at = tx_context::epoch(ctx);
        
        // Emit campaign updated event
        event::emit(CampaignUpdatedEvent {
            campaign_id: object::uid_to_address(&campaign.id),
            advertiser: object::uid_to_address(&advertiser.id),
            status: campaign.status,
            updated_at: campaign.updated_at,
        });
    }
    
    /// Cancel a campaign
    public entry fun cancel_campaign(
        registry: &mut AdRegistry,
        advertiser: &mut Advertiser,
        campaign: &mut Campaign,
        ctx: &mut TxContext
    ) {
        // Verify caller is the advertiser owner
        assert!(tx_context::sender(ctx) == advertiser.profile_id, EUnauthorized);
        assert!(campaign.advertiser == object::uid_to_address(&advertiser.id), EUnauthorized);
        
        // Verify campaign is not already completed or canceled
        assert!(
            campaign.status != CAMPAIGN_STATUS_COMPLETED && 
            campaign.status != CAMPAIGN_STATUS_CANCELED,
            ECampaignInactive
        );
        
        // Calculate refund amount (remaining budget)
        let refund_amount = campaign.remaining_budget;
        
        // Update campaign status
        campaign.status = CAMPAIGN_STATUS_CANCELED;
        campaign.updated_at = tx_context::epoch(ctx);
        campaign.end_time = tx_context::epoch(ctx); // End now
        
        // Process refund if there is a remaining budget
        if (refund_amount > 0) {
            // Create refund coin from remaining budget
            let refund = coin::from_balance(balance::split(&mut campaign.budget_balance, refund_amount), ctx);
            
            // Transfer refund to advertiser
            transfer::public_transfer(refund, advertiser.profile_id);
            
            // Update remaining budget
            campaign.remaining_budget = 0;
        };
        
        // Emit campaign updated event
        event::emit(CampaignUpdatedEvent {
            campaign_id: object::uid_to_address(&campaign.id),
            advertiser: object::uid_to_address(&advertiser.id),
            status: campaign.status,
            updated_at: campaign.updated_at,
        });
    }
    
    /// Add funds to a campaign
    public entry fun fund_campaign(
        registry: &mut AdRegistry,
        advertiser: &mut Advertiser,
        campaign: &mut Campaign,
        payment: &mut Coin<MYS>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Verify caller is the advertiser owner
        assert!(tx_context::sender(ctx) == advertiser.profile_id, EUnauthorized);
        assert!(campaign.advertiser == object::uid_to_address(&advertiser.id), EUnauthorized);
        
        // Verify payment
        assert!(coin::value(payment) >= amount, EInsufficientPayment);
        assert!(amount > 0, EInvalidBudget);
        
        // Verify campaign is active or paused
        assert!(
            campaign.status == CAMPAIGN_STATUS_ACTIVE || 
            campaign.status == CAMPAIGN_STATUS_PAUSED ||
            campaign.status == CAMPAIGN_STATUS_DRAFT,
            ECampaignInactive
        );
        
        // Calculate platform fee (10%)
        let platform_fee = (amount * PLATFORM_FEE_BPS) / 10000;
        let campaign_amount = amount - platform_fee;
        
        // Process payment
        let payment_coin = coin::split(payment, amount, ctx);
        let mut payment_balance = coin::into_balance(payment_coin);
        
        // Split platform fee and campaign budget
        let platform_fee_balance = balance::split(&mut payment_balance, platform_fee);
        
        // Add funds to campaign budget
        balance::join(&mut campaign.budget_balance, payment_balance);
        
        // Update campaign stats
        campaign.total_budget = campaign.total_budget + campaign_amount;
        campaign.remaining_budget = campaign.remaining_budget + campaign_amount;
        campaign.updated_at = tx_context::epoch(ctx);
        
        // Update advertiser stats
        advertiser.total_spent = advertiser.total_spent + amount;
        
        // Add platform fee to registry
        balance::join(&mut registry.platform_fees, platform_fee_balance);
        
        // Emit campaign funded event
        event::emit(CampaignFundedEvent {
            campaign_id: object::uid_to_address(&campaign.id),
            advertiser: object::uid_to_address(&advertiser.id),
            amount: campaign_amount,
            timestamp: tx_context::epoch(ctx),
        });
    }
    
    /// Record an ad engagement (can be called by authorized ad servers)
    public entry fun record_engagement(
        registry: &AdRegistry,
        admin_cap: &AdAdminCap,
        campaign: &mut Campaign,
        user: address,
        engagement_type: u8,
        ctx: &mut TxContext
    ) {
        // Verify caller is an admin 
        // Note: Instead of using object::owner, we use tx_context::sender to match with admin
        // This assumes the admin cap should only be in possession of the admin
        assert!(registry.admin == tx_context::sender(ctx), EUnauthorized);
        
        // Verify campaign is active
        assert!(campaign.status == CAMPAIGN_STATUS_ACTIVE, ECampaignInactive);
        
        // Verify campaign has not expired
        let now = tx_context::epoch(ctx);
        assert!(now <= campaign.end_time, ECampaignExpired);
        
        // Verify campaign has remaining budget
        assert!(campaign.remaining_budget > 0, EInvalidBudget);
        
        // Calculate engagement cost based on bid model and type
        let mut cost = calculate_engagement_cost(campaign, engagement_type);
        
        // Make sure cost doesn't exceed remaining budget
        if (cost > campaign.remaining_budget) {
            cost = campaign.remaining_budget;
        };
        
        // Update campaign stats based on engagement type
        if (engagement_type == ENGAGEMENT_VIEW) {
            campaign.impressions = campaign.impressions + 1;
        } else if (engagement_type == ENGAGEMENT_CLICK) {
            campaign.clicks = campaign.clicks + 1;
        } else if (engagement_type == ENGAGEMENT_INTERACTION) {
            campaign.engagements = campaign.engagements + 1;
        } else if (engagement_type == ENGAGEMENT_CONVERSION) {
            campaign.conversions = campaign.conversions + 1;
        };
        
        // Update remaining budget
        campaign.remaining_budget = campaign.remaining_budget - cost;
        
        // Create engagement record
        let engagement = Engagement {
            id: object::new(ctx),
            campaign_id: object::uid_to_address(&campaign.id),
            user,
            engagement_type,
            timestamp: now,
            cost,
        };
        
        // Share engagement record
        transfer::share_object(engagement);
        
        // Emit engagement event
        event::emit(AdEngagementEvent {
            campaign_id: object::uid_to_address(&campaign.id),
            user,
            engagement_type,
            cost,
            timestamp: now,
        });
        
        // Auto-complete campaign if budget is exhausted
        if (campaign.remaining_budget == 0) {
            campaign.status = CAMPAIGN_STATUS_COMPLETED;
            campaign.updated_at = now;
            
            // Emit campaign updated event
            event::emit(CampaignUpdatedEvent {
                campaign_id: object::uid_to_address(&campaign.id),
                advertiser: campaign.advertiser,
                status: campaign.status,
                updated_at: campaign.updated_at,
            });
        };
    }
    
    // === Admin Functions ===
    
    /// Update ad format base costs (admin only)
    public entry fun update_format_costs(
        registry: &AdRegistry,
        admin_cap: &AdAdminCap,
        feed_cost: u64,
        story_cost: u64,
        featured_cost: u64,
        banner_cost: u64,
        ctx: &mut TxContext
    ) {
        // Verify caller is admin
        // Note: Replaced object::owner with direct check against registry admin
        assert!(registry.admin == tx_context::sender(ctx), EUnauthorized);
        
        // We could store these in the registry instead of constants,
        // but for simplicity and to avoid modifying the registry structure,
        // we'll leave the function stub here
    }
    
    /// Set advertiser verification status (admin only)
    public entry fun set_advertiser_verification(
        registry: &AdRegistry,
        admin_cap: &AdAdminCap,
        advertiser: &mut Advertiser,
        verified: bool,
        ctx: &mut TxContext
    ) {
        // Verify caller is admin
        // Note: Replaced object::owner with direct check against registry admin
        assert!(registry.admin == tx_context::sender(ctx), EUnauthorized);
        
        // Update advertiser verification status
        advertiser.verified = verified;
    }
    
    /// Withdraw platform fees (admin only)
    public entry fun withdraw_platform_fees(
        registry: &mut AdRegistry,
        admin_cap: &AdAdminCap,
        ctx: &mut TxContext
    ) {
        // Verify caller is admin
        // Note: Replaced object::owner with direct check against registry admin
        assert!(registry.admin == tx_context::sender(ctx), EUnauthorized);
        
        // Get platform fees balance
        let amount = balance::value(&registry.platform_fees);
        
        // Only proceed if there's a non-zero balance
        if (amount > 0) {
            // Extract balance
            let fee_balance = balance::split(&mut registry.platform_fees, amount);
            
            // Convert to coin
            let fee_coin = coin::from_balance(fee_balance, ctx);
            
            // Transfer to admin
            transfer::public_transfer(fee_coin, registry.admin);
            
            // Emit fees withdrawn event
            event::emit(PlatformFeesWithdrawnEvent {
                amount,
                recipient: registry.admin,
                timestamp: tx_context::epoch(ctx),
            });
        };
    }
    
    // === Helper Functions ===
    
    /// Calculate engagement cost based on campaign bid model and engagement type
    fun calculate_engagement_cost(campaign: &Campaign, engagement_type: u8): u64 {
        let mut cost = campaign.bid_amount;
        
        if (campaign.bid_model == BID_MODEL_CPM && engagement_type == ENGAGEMENT_VIEW) {
            // CPM model: cost is bid_amount / 1000 for each view
            cost = campaign.bid_amount / 1000;
        } else if (campaign.bid_model == BID_MODEL_CPC && engagement_type == ENGAGEMENT_CLICK) {
            // CPC model: full bid_amount for each click
            cost = campaign.bid_amount;
        } else if (campaign.bid_model == BID_MODEL_CPE && 
                  (engagement_type == ENGAGEMENT_CLICK || engagement_type == ENGAGEMENT_INTERACTION)) {
            // CPE model: full bid_amount for clicks or interactions
            cost = campaign.bid_amount;
        } else if (campaign.bid_model == BID_MODEL_CPA && engagement_type == ENGAGEMENT_CONVERSION) {
            // CPA model: full bid_amount for conversions
            cost = campaign.bid_amount;
        } else {
            // Default case for other combinations (e.g., views for CPC campaigns)
            // Charge a minimal amount for tracking
            cost = 1;
        };
        
        cost
    }
    
    /// Get minimum budget for an ad format
    fun get_minimum_budget_for_format(format: u8): u64 {
        if (format == AD_FORMAT_FEED) {
            BASE_COST_FEED
        } else if (format == AD_FORMAT_STORY) {
            BASE_COST_STORY
        } else if (format == AD_FORMAT_FEATURED) {
            BASE_COST_FEATURED
        } else if (format == AD_FORMAT_BANNER) {
            BASE_COST_BANNER
        } else {
            BASE_COST_FEED // Default
        }
    }
    
    /// Build targeting criteria from vectors of types and values
    fun build_targeting_criteria(
        targeting_types: vector<u8>,
        targeting_values: vector<String>
    ): vector<TargetingCriteria> {
        let mut result = vector::empty<TargetingCriteria>();
        let mut i = 0;
        let len = vector::length(&targeting_types);
        
        while (i < len) {
            let targeting_type = *vector::borrow(&targeting_types, i);
            let value = *vector::borrow(&targeting_values, i);
            
            let criteria = TargetingCriteria {
                targeting_type,
                value,
            };
            
            vector::push_back(&mut result, criteria);
            i = i + 1;
        };
        
        result
    }
    
    /// Build ad creative from components
    fun build_ad_creative(
        title: String,
        content: String,
        media_url: vector<u8>,
        cta_text: String,
        destination_url: vector<u8>,
        ctx: &mut TxContext
    ): AdCreative {
        // Convert URLs if provided
        let media = if (vector::length(&media_url) > 0) {
            option::some(url::new_unsafe_from_bytes(media_url))
        } else {
            option::none()
        };
        
        let destination = if (vector::length(&destination_url) > 0) {
            option::some(url::new_unsafe_from_bytes(destination_url))
        } else {
            option::none()
        };
        
        AdCreative {
            title,
            content,
            media_url: media,
            cta_text,
            destination_url: destination,
        }
    }
    
    // === Getters ===
    
    /// Get campaign by ID
    public fun get_campaign_id(registry: &AdRegistry, campaign_id: address): Option<address> {
        if (table::contains(&registry.campaigns, campaign_id)) {
            option::some(*table::borrow(&registry.campaigns, campaign_id))
        } else {
            option::none()
        }
    }
    
    /// Get campaign for a post
    public fun get_post_campaign(registry: &AdRegistry, post_id: address): Option<address> {
        if (table::contains(&registry.post_campaigns, post_id)) {
            option::some(*table::borrow(&registry.post_campaigns, post_id))
        } else {
            option::none()
        }
    }
    
    /// Get advertiser's campaigns
    public fun get_advertiser_campaigns(registry: &AdRegistry, advertiser_id: address): vector<address> {
        if (table::contains(&registry.advertiser_campaigns, advertiser_id)) {
            *table::borrow(&registry.advertiser_campaigns, advertiser_id)
        } else {
            vector::empty()
        }
    }
    
    /// Check if campaign is active
    public fun is_campaign_active(campaign: &Campaign, clock: &Clock): bool {
        let now = clock::timestamp_ms(clock) / 1000;
        
        campaign.status == CAMPAIGN_STATUS_ACTIVE &&
        now >= campaign.start_time &&
        now <= campaign.end_time &&
        campaign.remaining_budget > 0
    }
    
    /// Get campaign status
    public fun get_campaign_status(campaign: &Campaign): u8 {
        campaign.status
    }
    
    /// Get campaign metrics
    public fun get_campaign_metrics(campaign: &Campaign): (u64, u64, u64, u64) {
        (campaign.impressions, campaign.clicks, campaign.engagements, campaign.conversions)
    }
    
    /// Get campaign targeting criteria
    public fun get_campaign_targeting(campaign: &Campaign): &vector<TargetingCriteria> {
        &campaign.targeting
    }
    
    /// Get campaign budgets
    public fun get_campaign_budgets(campaign: &Campaign): (u64, u64) {
        (campaign.total_budget, campaign.remaining_budget)
    }
    
    /// Get advertiser stats
    public fun get_advertiser_stats(advertiser: &Advertiser): (u64, u64, bool) {
        (advertiser.total_spent, advertiser.campaign_count, advertiser.verified)
    }
}