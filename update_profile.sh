#\!/bin/bash
# Script to update an existing profile with a cover photo and email

PACKAGE_ID="0xba5e43db920ce7b913b268c5c005bb02147173692767847d17225a3e8212f962"
PROFILE_ID="0x145a1969300e42eb012e25d8549f5474f80b7ca1a51d152f58b79493457dfeca"

myso client call --package $PACKAGE_ID \
  --module profile \
  --function update_profile \
  --args $PROFILE_ID \
  "Brandon Shaw" \
  "This is my updated bio with new fields" \
  "https://example.com/profile.jpg" \
  "https://example.com/cover_photo.jpg" \
  "brandon@example.com" \
  --gas-budget 10000000

# After update, query the profile object to see the changes
myso client object $PROFILE_ID
