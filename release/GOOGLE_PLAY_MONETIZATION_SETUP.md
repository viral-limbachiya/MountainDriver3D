# Google Play Monetization and Player Profile Setup

## One-time products

Create these as **one-time, non-consumable products** in Play Console. Product IDs must match exactly:

- `premium_rally_suv` - Rally Titan SUV
- `premium_velocity_car` - Velocity GT
- `premium_garage_max` - Max Garage Pack

Activate each product and add prices for all intended countries. The game loads the localized Google Play price automatically. These products are permanent and the **Restore Purchases** button queries Google Play ownership.

## Play Games Services

1. In Play Console, open **Grow users > Play Games Services > Setup and management > Configuration**.
2. Create or link a Play Games Services project.
3. Add Android credentials for package `com.vrlpro.mountaindriver3d` using the SHA-1 shown under **Setup > App integrity > App signing key certificate**.
4. Copy the numeric Game project ID into `android/build/res/values/strings.xml`, replacing `0`.
5. Create two leaderboards:
   - Lifetime Coins: larger score is better.
   - Best Distance: larger score is better; unit can be metres.
6. Copy their IDs into `LEADERBOARD_LIFETIME_COINS` and `LEADERBOARD_BEST_DISTANCE` near the top of `scripts/main.gd`.
7. Enable Saved Games in Play Games Services so `mountain_driver_profile` can sync lifetime coins, best distance and completed runs.
8. Add closed-test Google accounts as Play Games testers and publish the Play Games configuration.

## Testing

- Upload version code 3 to a closed-testing release.
- Install only from the closed-test Play Store link; Billing does not work correctly with a manually installed build.
- Use a license tester account to test purchases without real charges.
- Test purchase cancellation, pending payment, restore after reinstall, selecting both cars, and the max garage pack.

## Security model

Permanent product ownership comes from Google Play Billing. Earned lifetime statistics use local save plus Play Games Saved Games and leaderboards. Do not add purchasable consumable coin packs without a secure backend that verifies and consumes purchase tokens.
