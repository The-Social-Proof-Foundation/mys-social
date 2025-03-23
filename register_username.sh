#!/bin/bash
# Script to register a username with the simplified one-username-per-profile logic

# Replace these IDs with your actual values after publishing
PACKAGE_ID="0xba5e43db920ce7b913b268c5c005bb02147173692767847d17225a3e8212f962"
REGISTRY_ID="0x4c23ca5af8eed10ea709385c91b29e185d67657943ca8d2f21fe4208561461b5"
PROFILE_ID="0x145a1969300e42eb012e25d8549f5474f80b7ca1a51d152f58b79493457dfeca"
COIN_ID="0x4686b72f1ef73585de844c8711655a28d69ce2fd0dab4110bce5757dfdcdace8"
CLOCK_ID="0x6"

# Step 1: Create a registry if not already created
# Uncomment if you need to create a new registry
# echo "Creating name registry..."
# myso client call --package $PACKAGE_ID \
#   --module name_service \
#   --function create_and_share_registry \
#   --gas-budget 10000000

# Step 2: Register a username and assign to profile in one step
echo "Registering username and assigning to profile..."
myso client call --package $PACKAGE_ID \
  --module name_service \
  --function register_username \
  --args $REGISTRY_ID $PROFILE_ID "mynewusername" $COIN_ID $CLOCK_ID \
  --gas-budget 10000000

# Step 3: Verify the registration
echo "Profile object:"
myso client object $PROFILE_ID

echo "Registry object:"
myso client object $REGISTRY_ID

echo "Checking for username associated with profile:"
myso client call --package $PACKAGE_ID \
  --module name_service \
  --function get_username_for_profile \
  --args $REGISTRY_ID $PROFILE_ID \
  --gas-budget 10000000

# Step 4: Try to register a second username (should fail with EUserAlreadyHasUsername)
# echo "Attempting to register a second username (should fail)..."
# myso client call --package $PACKAGE_ID \
#   --module name_service \
#   --function register_username \
#   --args $REGISTRY_ID $PROFILE_ID "mysecondusername" $COIN_ID $CLOCK_ID \
#   --gas-budget 10000000