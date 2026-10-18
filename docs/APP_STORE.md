# App Store

## In-app purchases

Create these in App Store Connect > your app > Monetization. The IDs must match `OX_PREMIUM_PRODUCT_IDS` in `Config/Base.xcconfig`:

| Product ID | Type | Suggested price |
|---|---|---|
| `com.oxydemap.premium.monthly` | Auto-renewable subscription, group "Oxyde Premium" | 2.99 |
| `com.oxydemap.premium.yearly` | Auto-renewable subscription, same group | 19.99 |
| `com.oxydemap.premium.lifetime` | Non-consumable | 39.99 |

If you use a different bundle prefix, change the IDs in both places. Prices in the app always come from the App Store; none are hardcoded.

Premium unlocks the 4 premium themes only. Navigation, voice, rerouting, traffic, reports and CarPlay are free, as guideline 5 and the brief require for safety features.

## Review notes to include

- "Oxyde Map is a turn-by-turn navigation app using Apple MapKit. Background location is used only during active navigation for spoken directions."
- "Community reports come from drivers and are labeled as unverified in the app."
- "Police and speed-camera reporting is disabled in countries where it is restricted."
- Provide a short demo route in a city of your choice and mention that reports need location.

## Checklist before submission

- [ ] Privacy policy URL (docs/PRIVACY.md has the content)
- [ ] Privacy nutrition label (docs/PRIVACY.md)
- [ ] Screenshots for 6.9" and 6.5" iPhone. Take them from TestFlight on your iPhone 14, or from the simulator on a Mac.
- [ ] Age rating questionnaire
- [ ] Subscription terms text in the description: price, period, auto-renewal, how to cancel
- [ ] Legal review of report region rules for each launch country
- [ ] Backend deployed on HTTPS, with `OX_BACKEND_BASE_URL` set
- [ ] CarPlay: submit only with the full entitlements file after Apple grants the entitlement
