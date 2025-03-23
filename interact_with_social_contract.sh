#\!/bin/bash

# Package ID of the published MySocialContracts contract
PACKAGE_ID=0xf16b6567d925341ab29edcf9e0dd743530f235083b2ac2603dbe6e37832eafef
GAS_BUDGET=1000000000

# 1. Create and share name registry
echo "Creating Name Registry..."
myso client call --package $PACKAGE_ID --module name_service --function create_and_share_registry --gas-budget $GAS_BUDGET

# 2. Create a profile
echo "Creating Profile..."
myso client call --package $PACKAGE_ID --module profile --function create_profile --args "User Name" "This is my bio" "https://example.com/profile.jpg" --gas-budget $GAS_BUDGET

# After profile is created, get the profile object ID from output
echo "Now get your profile ID from the transaction output"
echo "Run:"
echo "myso client object [PROFILE_ID]"

# 3. Register a username and assign it to profile
echo "To register a username and assign it to your profile, run:"
echo "myso client call --package $PACKAGE_ID --module name_service --function register_and_assign_username --args [REGISTRY_ID] [PROFILE_ID] \"username\" [COIN_OBJECT_ID] 1 [CLOCK_OBJECT_ID] --gas-budget $GAS_BUDGET"

# 4. Get system clock object
echo "To get the system clock object ID, run:"
echo "myso client object 0x6"

# 5. View profile
echo "To view your profile after registration, run:"
echo "myso client object [PROFILE_ID]"

