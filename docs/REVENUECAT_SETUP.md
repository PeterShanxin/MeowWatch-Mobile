# RevenueCat Test Store setup

Dashboard configuration verified on 2026-09-16:

- Project: `MeowWatch Mobile`
- Project ID: `ca9218b2`
- Platform/category selected during project creation: Flutter / Entertainment
- App/store: `Test Store`
- Test Store app ID: `appb0065eafd5`
- Entitlement: `meowwatch_plus` (`entlf906cb5cf4`)
- Product: `meowwatch_plus_monthly` (`prod8cb5d7507d`)
  - Display name: `MeowWatch Plus Monthly`
  - Customer-facing name: `MeowWatch Plus`
  - Type/duration: auto-renewing subscription / monthly
  - Test price: USD 2.99 per month
- Current offering: `default` (`ofrngf59b39f16a`)
  - Package: `Monthly` / `$rc_monthly`
  - Product: `meowwatch_plus_monthly`

The USD 2.99 amount is simulated Test Store pricing for development and the
Shipaton demo. It is not a commercial pricing decision. Choose regional store
pricing separately before a real launch.

The Shipaton build defaults to this project's public Test Store SDK key in
`lib/app/app_services.dart`, so a clean judge installation can retrieve the real
offering immediately. Public SDK keys are client configuration, not server
credentials. `REVENUECAT_API_KEY` can override it at build time, as described in
[BILLING.md](BILLING.md). Never commit a RevenueCat secret/server key. The default
Test Store cannot charge a real payment method.

The dashboard account showed an unconfirmed email banner during setup. This did
not block catalog configuration, but the account owner should confirm the email
before depending on account recovery or final submission access.

The dashboard configuration does not prove Android purchase behavior. Complete
the device/Test Store matrix in [BILLING.md](BILLING.md) before marking RevenueCat
acceptance complete.
