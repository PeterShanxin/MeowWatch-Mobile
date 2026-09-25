# Shipaton 2026 Next Gen submission requirements

Verified against the current primary sources on 2026-09-16. The English
[Official Rules on Devpost](https://revenuecat-shipaton-2026.devpost.com/rules)
control if another Shipaton page or translation differs.

The deadline, explicit Next Gen no-store path and organizer's Test Store answer
were rechecked on September 24. The complete authenticated form and English
rules were re-read on September 25. The first-version/store checkbox is now
optional; it is left unanswered for this no-store Next Gen entry.

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

### Current form and remaining rules interpretation

The controlling English rules were re-read through Devpost on September 25.
They retain the following tension:

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

Operationally, use the explicit English no-store Next Gen path, disclose the
desktop heritage, and retain the separate Android development history and
license provenance. Organizer clarification of the mobile counterpart's
new-work status is still outstanding; registration is not a ruling on that
question. No message to the organizer has been sent on the entrant's behalf.

The complete authenticated Devpost submission form was re-read on September 25
at 07:19 UTC. **First Version Date Confirmation (27380) is now optional**, as
are the three store URL fields. Leave these unanswered for this no-store entry;
the earlier required-store-checkbox concern is no longer a form blocker.
The form requires icon confirmation (27378), unframed screenshot confirmation
(27379), supported platform (27382; Android), and RevenueCat project ID (28118).
Next Gen additionally needs repository URL (27793) and qualifying academic email
(27792), even though those category-specific fields are optional globally.
Do not infer email, staff/sponsor status, promotional codes or growth-fund opt-in.

On 2026-09-17, the entrant confirmed active student status, reaching the local
age of majority, and availability of a student/academic email for Devpost. No
email address was collected at that time. The entrant subsequently provided an
academic email and authorized its use; it is saved only in the Devpost form,
not this repository. On September 25 the domain was checked against JetBrains/swot,
including its documented coverage of subdomains. The entrant also confirmed
GitHub sign-in uses the school email. This records domain coverage and the
entrant's statement, not an independent Devpost eligibility decision.
On September 25 the entrant explicitly accepted the official
rules and Devpost terms and confirmed registration eligibility. Registration
succeeded, and [MeowWatch Mobile](https://devpost.com/software/meowwatch-mobile)
was initially saved as an authenticated **Draft**. Its description,
technology tags, source links, gallery cover, original icon/screenshot, Android
platform, RevenueCat project ID and judge notes are saved. At that earlier
browser checkpoint the UI reported **3/5 steps done**. The final public video
URL and submission still need completion; that earlier progress count is not
a current submission receipt.
Personal registration answers are not stored in this repository.

The project connector's September 25 13:53 UTC description update published the
project page (version 3). Readback confirms `state: published` and a null
hackathon `submitted_at`: the public portfolio page is not a submitted entry.
The live submission requirements were fetched immediately beforehand and still
show the first-version/store checkbox as optional. No additional mandatory
ownership/new-work declaration appears in the complete field list. The
entrant's accepted rules and the disclosed desktop heritage remain applicable.
Following the owner's instruction to update the video and submission link,
the final [YouTube video](https://youtu.be/gRUYlHb3LiI) is saved as Unlisted with
HD processing complete. The project connector's video URL is verified, and the
actual competition form also saves the URL and updated judge notes, reaching
**4/5 steps done**. The final Submit page is available; the entry remains a draft
pending repository closeout and final submission.

An authenticated Devpost account read on September 25 confirms the account
email exactly matches the academic address already authorized for the entry.
The address is deliberately excluded from this repository. This closes the
account-email check, not an independent organizer eligibility determination.
