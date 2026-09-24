# Shipaton 2026 Next Gen submission requirements

Verified against the current primary sources on 2026-09-16. The English
[Official Rules on Devpost](https://revenuecat-shipaton-2026.devpost.com/rules)
control if another Shipaton page or translation differs.

The deadline, explicit Next Gen no-store path and organizer's Test Store answer
were rechecked on 2026-09-24 at the linked primary sources below. They remain
unchanged. The organizer discussion still has no answer to the required
store-release checkbox follow-up; do not attest to a store release that did not
happen.

## Confirmed submission path

- **Category and entrant:** Next Gen is for an active student aged 13 or older
  who is enrolled in high school, college, university, bootcamp, or another
  academic program. A qualifying student or academic email must be used on
  Devpost; the domain may be checked with JetBrains/swot. Entrants below the age
  of majority require a parent or legal guardian to accept the rules and submit
  the consent form. These are entrant facts that this repository cannot verify.
  ([Official Rules, sections 3 and 4](https://revenuecat-shipaton-2026.devpost.com/rules),
  [Next Gen page](https://www.shipaton.com/next-gen))
- **Eligible product platform:** The submitted project must run on Android,
  iOS, iPadOS, or macOS. Android is therefore eligible.
  ([Official Rules, Project Requirements](https://revenuecat-shipaton-2026.devpost.com/rules))
- **No store release required for Next Gen:** A paid Apple or Google developer
  account and an app-store release are not required. Next Gen is evaluated from
  its demo video and public source repository; a store release is not considered
  in Next Gen judging.
  ([Official Rules, Submission Requirements and Testing](https://revenuecat-shipaton-2026.devpost.com/rules),
  [Next Gen page](https://www.shipaton.com/next-gen),
  [FAQ](https://www.shipaton.com/faq))
- **Deadline:** Submit on Devpost by **Wednesday, 2026-09-30 at 11:45 PM PDT**.
  This is **2026-10-01 at 2:45 PM in China Standard Time**. The rules allow the
  sponsor to change dates, so recheck the Devpost countdown on submission day.
  ([Official Rules, section 1](https://revenuecat-shipaton-2026.devpost.com/rules),
  [submission guide](https://www.shipaton.com/blog/how-to-submit-your-app-for-shipaton))

## RevenueCat purchase evidence

Every entry must use the RevenueCat SDK to power at least one in-app or web
purchase, or use RevenueCat Ads. Merely adding or initializing the package does
not demonstrate the required purchase flow.
([Official Rules, Project Requirements](https://revenuecat-shipaton-2026.devpost.com/rules))

**RevenueCat Test Store is sufficient for Next Gen.** A Shipaton Manager answered
this exact question on the official Devpost discussion. The confirmed scenario
was an Offering loaded through the SDK, a completed Test Store purchase,
`CustomerInfo` entitlement activation, and a real entitlement-backed feature
unlock, with no store listing or real payment.
([official organizer answer](https://revenuecat-shipaton-2026.devpost.com/forum_topics/44695-next-gen-eligibility-is-a-test-store-only-purchase-sufficient))

For this Flutter project:

- use the official `purchases_flutter` SDK, version **9.8.0 or later** for Test
  Store support;
- configure products, an Offering, and `meowwatch_plus` entitlement in the
  RevenueCat project;
- show Offering retrieval, successful purchase, updated `CustomerInfo`, the
  entitlement-backed unlimited-hosting behavior, and restore/relaunch behavior;
- exercise cancellation and failure paths even if the short submission video
  only shows the successful path; and
- use the Test Store API key only for the non-store build. RevenueCat explicitly
  says never to submit an App Store or Google Play build configured with a Test
  Store API key.

Test Store purchases are sandbox data but otherwise update `CustomerInfo`, grant
entitlements subject to sandbox-access settings, and provide success, failure,
and cancellation outcomes.
([RevenueCat Test Store](https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store),
[Flutter installation](https://www.revenuecat.com/docs/getting-started/installation/flutter),
[Shipaton resources](https://revenuecat-shipaton-2026.devpost.com/resources))

The Next Gen judging criteria specifically ask whether RevenueCat is used
thoughtfully for a monetization flow. The demo should therefore show the
purchase-to-entitlement-to-product-benefit chain, not a detached test dialog.
([Official Rules, Next Gen Award Criteria](https://revenuecat-shipaton-2026.devpost.com/rules))

## Required submission artifacts

Prepare all of the following before the deadline:

| Artifact | Exact requirement | Evidence |
| --- | --- | --- |
| Public source repository | Public and open source; includes every necessary source file, asset, and setup/run instruction; includes an open-source license file that is detectable and visible in the repository's **About** area. | [Official Rules, Submission Requirements](https://revenuecat-shipaton-2026.devpost.com/rules) |
| Written project description | Explain the project's features and functionality. Submission materials must be English, or include an English translation. | [Official Rules, Submission and Language Requirements](https://revenuecat-shipaton-2026.devpost.com/rules) |
| Demo video | **Strictly less than 2:00**; show the working app on the device/platform for which it was built; publicly visible on YouTube or Vimeo. An unlisted YouTube video is acceptable, but a private video is not. Do not include third-party trademarks, copyrighted music, or other protected material without permission. | [Official Rules, Submission Requirements](https://revenuecat-shipaton-2026.devpost.com/rules), [submission guide](https://www.shipaton.com/blog/how-to-submit-your-app-for-shipaton) |
| App icon | Exactly **1024 x 1024 px**. | [Official Rules, Submission Requirements](https://revenuecat-shipaton-2026.devpost.com/rules) |
| App screenshot | At least one, exactly **1179 px wide x 2556 px high**, with **no device frame**. The official guide recommends showing the core experience, RevenueCat use, and the product's strongest point. | [Official Rules, Submission Requirements](https://revenuecat-shipaton-2026.devpost.com/rules), [submission guide](https://www.shipaton.com/blog/how-to-submit-your-app-for-shipaton) |
| RevenueCat project ID | Enter the ID from RevenueCat Project settings in the Devpost form. | [submission guide](https://www.shipaton.com/blog/how-to-submit-your-app-for-shipaton) |
| Project overview | Project name, short tagline, and gallery thumbnail. Devpost recommends a readable **3:2** JPG, PNG, or GIF thumbnail; no exact pixel dimensions are specified in the guide. | [submission guide](https://www.shipaton.com/blog/how-to-submit-your-app-for-shipaton) |
| Next Gen proof | Use the qualifying academic email on Devpost and provide the public repository URL plus the demo video. | [Official Rules, Next Gen requirements](https://revenuecat-shipaton-2026.devpost.com/rules) |

Next Gen does **not** require an app-store URL, free trial, or promo code. Those
requirements apply to non-Next-Gen entries. The final Devpost state must show
**Submitted** and all **5/5** sections complete; a saved draft is not a submission.
([Official Rules, Submission Requirements](https://revenuecat-shipaton-2026.devpost.com/rules),
[submission guide](https://www.shipaton.com/blog/how-to-submit-your-app-for-shipaton))

The rules require an identifiable open-source license but do not prescribe
AGPL-3.0-only or any other specific license. AGPL-3.0-only is this project's
chosen compatibility policy from [PRODUCT_SPEC.md](PRODUCT_SPEC.md), not a
Shipaton rule. Keep the public repository and video accessible from the United
States during judging.
([Official Rules, Project, Submission, and Testing Requirements](https://revenuecat-shipaton-2026.devpost.com/rules))

The first two minutes of the demo should cover the app's pitch, core experience,
purchase/subscription experience, and why it fits Next Gen. Because the limit is
strictly less than two minutes, target a final encoded duration with a small
margin rather than exactly `02:00.000`.
([submission guide](https://www.shipaton.com/blog/how-to-submit-your-app-for-shipaton))

## Existing Windows MeowWatch and the new-work rule

The existing public MeowWatch repository describes a shipped Windows x64 alpha
with synchronized playback, floating chat, and many releases. MeowWatch Mobile
must therefore be presented truthfully as a new Android-first project and mobile
counterpart, not as the first existence of the MeowWatch concept.
([desktop repository](https://github.com/PeterShanxin/MeowWatch))

The rules permit a submission to use open-source software when the applicable
licenses are followed and the submission enhances and builds on the underlying
open-source product. They also require the submission to be the entrant's
original work and not violate another party's rights. Reused desktop code must
therefore retain required notices and clear provenance, and the entrant must
verify ownership or licensing for every reused contribution and asset.
([Official Rules, Submission ownership and Intellectual Property](https://revenuecat-shipaton-2026.devpost.com/rules))

The safest evidence of substantial new mobile work is:

- a separate mobile repository and commit history during the submission window;
- Android-native playback, lifecycle, permissions, navigation, and touch UI;
- mobile-specific RevenueCat integration and entitlement-backed behavior;
- nearby discovery, authenticated pairing, and companion UI; and
- a README that clearly identifies the pre-existing desktop project and lists
  reused modules and their license/provenance.

These facts strengthen the new-work case but do not themselves decide legal or
competition eligibility.

### Unresolved rules conflict

The current controlling English Devpost rules are internally inconsistent:

1. Project Requirements say every project's first public version must be
   released to an eligible store during the submission period, without a Next
   Gen exception.
2. Later clauses say Next Gen requires no store release and is judged from the
   video and repository.
3. The unofficial [French](https://www.shipaton.com/fr/rules) and
   [Portuguese](https://www.shipaton.com/pt-br/rules) translations resolve the
   conflict by exempting Next Gen from the store-release rule and adding that a
   Next Gen project must be new or created/substantially developed during the
   submission period. Both translations state that English controls.

Operationally, follow the stricter translated new/substantial-work standard and
the explicit English no-store Next Gen path. Before final submission, a human
should obtain written organizer clarification on these two precise questions:

1. Does a new Android-first mobile counterpart to an existing public Windows
   MeowWatch qualify when the Android project is built substantially during the
   submission window and any desktop code is reused under its open-source
   license?
2. If the Devpost form still requires the store-release checkbox, how should a
   no-store Next Gen entrant answer it truthfully? The existing official forum
   thread confirms Test Store sufficiency but leaves this checkbox follow-up
   unanswered.

On 2026-09-17, the entrant confirmed active student status, reaching the local
age of majority, and availability of a student/academic email for Devpost. No
email address was collected. Domain recognition in the actual Devpost path is
still unverified. Residency, ownership of prior work, absence of conflicts and
final legal acceptance remain separate entrant confirmations.
