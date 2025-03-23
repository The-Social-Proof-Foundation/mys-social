module social_contracts::my_ip {
    use std::string::{Self, String};
    use mys::object::{Self, UID};
    use mys::tx_context::{Self, TxContext};
    use mys::transfer;
    
    /// Error codes
    const EUnauthorized: u64 = 0;
    
    /// Intellectual property object
    public struct MyIP has key, store {
        id: UID,
        name: String,
        description: String,
        creator: address,
        creation_time: u64,
    }
    
    /// Create a new IP object
    public fun create(
        name: String,
        description: String,
        ctx: &mut TxContext
    ): MyIP {
        MyIP {
            id: object::new(ctx),
            name,
            description,
            creator: tx_context::sender(ctx),
            creation_time: tx_context::epoch_timestamp_ms(ctx),
        }
    }
    
    /// Get creator of the IP
    public fun creator(ip: &MyIP): address {
        ip.creator
    }
    
    /// Get name of the IP
    public fun name(ip: &MyIP): String {
        ip.name
    }
    
    /// Get description of the IP
    public fun description(ip: &MyIP): String {
        ip.description
    }
    
    /// Get creation time of the IP
    public fun creation_time(ip: &MyIP): u64 {
        ip.creation_time
    }
    
    // Added for proof of creativity integration
    public fun set_poc_id(ip: &mut MyIP, poc_id: address) {
        // We would normally add a field to store this, but for now
        // just make it a no-op for compatibility
    }
}