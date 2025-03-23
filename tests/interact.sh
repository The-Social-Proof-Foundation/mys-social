#!/bin/bash

# MySocial Contract Interaction Script
# A comprehensive script for interacting with the MySocial smart contracts

# Package ID of the published MySocialContracts contract
PACKAGE_ID=0xf16b6567d925341ab29edcf9e0dd743530f235083b2ac2603dbe6e37832eafef
GAS_BUDGET=1000000000
CLOCK_ID=0x6

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

# Show main menu
show_menu() {
    print_header "MySocial Contract Interaction Menu"
    echo "1. Create Name Registry"
    echo "2. Create Profile"
    echo "3. Register Username"
    echo "4. Update Profile"
    echo "5. Create Post"
    echo "6. Follow User"
    echo "7. Query User Data"
    echo "8. View Object Details"
    echo "9. Exit"
    echo ""
    read -p "Select an option [1-9]: " choice
    
    case $choice in
        1) create_registry ;;
        2) create_profile ;;
        3) register_username ;;
        4) update_profile ;;
        5) create_post ;;
        6) follow_user ;;
        7) query_user ;;
        8) view_object ;;
        9) exit 0 ;;
        *) echo "Invalid option" && show_menu ;;
    esac
}

# Create Name Registry
create_registry() {
    print_header "Creating Name Registry"
    
    print_info "Creating and sharing name registry..."
    myso client call --package $PACKAGE_ID --module name_service --function create_and_share_registry --gas-budget $GAS_BUDGET
    
    print_success "Registry created! Save the registry ID from the transaction output."
    print_info "Look for an object with the 'NameRegistry' type in the transaction effects."
    
    read -p "Press Enter to continue..."
    show_menu
}

# Create Profile
create_profile() {
    print_header "Creating Profile"
    
    read -p "Enter display name: " display_name
    read -p "Enter bio: " bio
    read -p "Enter profile picture URL: " profile_pic
    
    print_info "Creating profile..."
    myso client call --package $PACKAGE_ID --module profile --function create_profile --args "$display_name" "$bio" "$profile_pic" --gas-budget $GAS_BUDGET
    
    print_success "Profile created! Save the profile ID from the transaction output."
    print_info "Look for an object with the 'Profile' type in the transaction effects."
    
    read -p "Press Enter to continue..."
    show_menu
}

# Register Username
register_username() {
    print_header "Registering Username"
    
    read -p "Enter registry ID: " registry_id
    read -p "Enter profile ID: " profile_id
    read -p "Enter desired username: " username
    read -p "Enter coin object ID (for payment): " coin_id
    read -p "Enter registration duration (in epochs): " duration
    
    print_info "Registering username '$username' and assigning to profile..."
    myso client call --package $PACKAGE_ID --module name_service --function register_and_assign_username --args "$registry_id" "$profile_id" "$username" "$coin_id" "$duration" "$CLOCK_ID" --gas-budget $GAS_BUDGET
    
    print_success "Username registered and assigned to profile!"
    
    read -p "Press Enter to continue..."
    show_menu
}

# Update Profile
update_profile() {
    print_header "Updating Profile"
    
    read -p "Enter profile ID: " profile_id
    read -p "Enter new display name: " display_name
    read -p "Enter new bio: " bio
    read -p "Enter new profile picture URL: " profile_pic
    
    print_info "Updating profile..."
    myso client call --package $PACKAGE_ID --module profile --function update_profile --args "$profile_id" "$display_name" "$bio" "$profile_pic" --gas-budget $GAS_BUDGET
    
    print_success "Profile updated!"
    
    read -p "Press Enter to continue..."
    show_menu
}

# Create Post
create_post() {
    print_header "Creating Post"
    
    read -p "Enter profile ID: " profile_id
    read -p "Enter post content: " content
    read -p "Enter media URL (leave empty if none): " media_url
    read -p "Enter hashtags (comma separated): " hashtags
    
    print_info "Creating post..."
    myso client call --package $PACKAGE_ID --module post --function create_post --args "$profile_id" "$content" "$media_url" "$hashtags" --gas-budget $GAS_BUDGET
    
    print_success "Post created!"
    
    read -p "Press Enter to continue..."
    show_menu
}

# Follow User
follow_user() {
    print_header "Following User"
    
    read -p "Enter your profile ID: " follower_id
    read -p "Enter profile ID to follow: " following_id
    
    print_info "Following user..."
    myso client call --package $PACKAGE_ID --module social_graph --function follow --args "$follower_id" "$following_id" --gas-budget $GAS_BUDGET
    
    print_success "Now following user!"
    
    read -p "Press Enter to continue..."
    show_menu
}

# Query User Data
query_user() {
    print_header "Querying User Data"
    
    read -p "Enter profile or object ID to query: " object_id
    
    print_info "Fetching object data..."
    myso client object $object_id
    
    read -p "Press Enter to continue..."
    show_menu
}

# View Object Details
view_object() {
    print_header "View Object Details"
    
    read -p "Enter object ID: " object_id
    
    print_info "Fetching object data..."
    myso client object $object_id
    
    read -p "Press Enter to continue..."
    show_menu
}

# Start the script
print_header "MySocial Contract Interaction Tool"
print_info "Package ID: $PACKAGE_ID"
show_menu