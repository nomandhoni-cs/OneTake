## ADDED Requirements

### Requirement: Products, purchase, restore
The system SHALL load the Annual (with 7-day introductory offer), Monthly, and
Lifetime products via RevenueCat, let the user purchase the selected product,
and offer Restore (RevenueCat sync + entitlement refresh). CustomerInfo from
the SDK SHALL be the entitlement truth. Failures SHALL map to human
strings; raw SDK error text SHALL never display.

#### Scenario: Annual shows trial
- **WHEN** the paywall loads with the Annual introductory offer configured
- **THEN** its row reads trial terms (e.g. "7 days free, then $12.99/yr") derived from the offer object

#### Scenario: Purchase unlocks Pro
- **WHEN** an Annual purchase transacts and verifies
- **THEN** `isPro` becomes true, persists across relaunch, and gates open

#### Scenario: Restore recovers Pro
- **WHEN** a previously-subscribed user taps Restore
- **THEN** entitlements refresh and `isPro` becomes true without repurchasing

### Requirement: Entitlement cache and gates
`isPro` SHALL be cached on-device (usable offline) and refreshed at launch,
foreground, and after purchase/restore. Record (Studio) and export/save
(Review) SHALL present the paywall sheet when not Pro; launch and the library
SHALL never block.

#### Scenario: Locked record opens paywall
- **WHEN** a non-Pro user taps Record
- **THEN** the paywall sheet appears instead of recording; closing it returns to Studio

#### Scenario: Pro survives offline relaunch
- **WHEN** a Pro user relaunches with no connectivity
- **THEN** cached `isPro` still opens record and export with no network call
