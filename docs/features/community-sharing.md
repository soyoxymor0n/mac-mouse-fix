# Community config sharing (opt-in)

Status: phase 0 done (2026-10-25). The curated repository is public at https://github.com/soyoxymor0n/mac-mouse-fix-setups (validator, fixtures, CI, one approving review on main). No app change and no server. Phases 1 and 2 (the in-app download, the upload) wait for your decisions on the controller question and the consent model. This plan is not legal advice. Items marked "question for you" need a decision or a lawyer.

## 1. Summary

Users could opt in to share the rows of one app tab (never their whole config) and download setups that other users shared. The research says the in-app upload should wait: a curated GitHub repository with CI validation and pull-request review costs nothing and buys time to settle consent and layout. If demand appears, a Cloudflare Worker with D1 is the next step, with downloading and sharing consented separately. Your current framing, "I get community knowledge in return for sharing", ties downloads to sharing, which is the main GDPR risk in this plan (section 7). CloudKit and Supabase are weaker fits, for the reasons in section 6.

## 2. Goals and non-goals

Goals:
- Let users download community setups for an app and add one to an app tab, using the same flow as presets.
- Let users opt in to share one app tab's rows, with a preview of the exact data sent.
- Let users delete their shared setups in one click, with no account.
- Keep personal data to the minimum, and keep sharing off until the user turns it on.

Non-goals:
- Accounts, profiles, ratings, comments or free text in v1.
- Sharing the whole config, the license, the device identifiers or any telemetry.
- Automatic sharing, or sharing from the Global tab.
- A server that learns which apps a user has. Downloads must not reveal the user's app list.

## 3. Research findings

Verified facts in this repository:
- The config holds a `License` section with `licenseStateCacheHash_AgainstDeviceUID` (`Shared/Config/default_config.plist`, `License` dict). A device-linked hash must never be uploaded. So the submission must contain only the app-tab rows, never a copy of `config.plist`.
- The app already defines network endpoints on `raw.githubusercontent.com` for the website and the update feed (`Shared/Constants.h` lines 88-89). So a read-only GitHub download is consistent with the current app, but it would be the first user-related data flow beyond updates. Check this in the privacy note.
- Config changes made by the main app reach the helper through `commitConfig()` and the `configFileChanged` message (`Shared/Config/Config.m` lines 134-145). The helper has no network role today. Keep it that way.
- The config has a `configVersion` (24) and migration steps (`Config.m` lines 513-602). A new consent key needs a version bump.
- The helper converts rows into its internal dictionary without a separate validation step (`Helper/Core/Remap/Remap.m`, lines 209-221). I found no shared row validator in the repository. This search was not exhaustive, so confirm before relying on it.

Verified facts from vendor and standards sources:
- GitHub Actions usage is free for public repositories that use standard GitHub-hosted runners. Private repositories get 2,000 minutes a month on GitHub Free. [GitHub Docs](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- Cloudflare Workers Free: 100,000 requests a day, 10 ms CPU per invocation. Workers Paid: $5 a month minimum, 10 million requests included, then $0.30 per million (page dated October 2, 2026). [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- Cloudflare D1 Free: 5 million rows read and 100,000 written a day, 5 GB total storage. D1 Paid: 50 million writes included a month, then $1.00 per million. The page says nothing about data location or EU jurisdiction. [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/)
- Supabase Free: 500 MB database, 50,000 monthly active users, 1 GB file storage, 5 GB egress. Free projects are paused after one week of inactivity. Pro is "from $25/month". The pricing page does not say whether EU regions exist. [Supabase pricing](https://supabase.com/pricing)
- CloudKit: Apple says the public database can hold "up to 1PB" of public app data. An older technote says 1 TB, and forum posts quote old per-container limits, so treat the numbers as unreliable. The page says nothing about data location. The Developer Program License Agreement lets Apple delete public container data when the agreement ends (agreement read via search summary only). [Apple CloudKit](https://developer.apple.com/icloud/cloudkit/), [agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
- GDPR Article 7(3): "It shall be as easy to withdraw as to give consent." Article 7(4): "utmost account shall be taken of whether" performance of a service "is conditional on consent to the processing of personal data that is not necessary for the performance of that contract." Article 9(1) lists health data and religious or political beliefs as special categories; Article 9(2)(a) allows explicit consent. [Article 7](https://gdpr-info.eu/art-7-gdpr/), [Article 9](https://gdpr-info.eu/art-9-gdpr/)

Not verified:
- EU data location for Cloudflare D1 and Supabase, and whether Turnstile, Cloudflare Access, D1 backups, or Supabase GitHub or Apple login are on your plan. Check the dashboards and the Cloudflare documentation.
- Whether an Apple Developer Program membership is required for CloudKit containers. The search did not settle this.
- EU-US Data Privacy Framework listings and data processing agreements for all four providers. Check each provider's site.

## 4. Data model

Submission (what the app uploads, one per app tab, and only after consent):

```json
{
  "schemaVersion": 1,
  "bundleID": "com.microsoft.teams2",
  "rows": [
    { "trigger": { "button": 4, "duration": "click", "level": 1 }, "modifiers": {}, "effect": { "type": "keyboardShortcut", "keycode": 46, "flags": 1179648 }, "app": "com.microsoft.teams2" },
    { "trigger": { "button": 5, "duration": "click", "level": 1 }, "modifiers": {}, "effect": { "type": "keyboardShortcut", "keycode": 31, "flags": 1179648 }, "app": "com.microsoft.teams2" }
  ],
  "appVersion": "3.x.x (from the app's own version string)",
  "submittedAt": "2026-10-25T12:00:00Z"
}
```

The rows keep the existing format, including `app`, so the same import code can be used. Nothing else is sent.

Server record (after review): `id`, `status`, the submission, `deleteTokenHash` (SHA-256 of the device's random delete secret, kept in the Keychain), `receivedAt` and `reportCount`. The record holds no name, e-mail address, account or IP address. IP addresses appear only in short-lived rate-limit counters (section 7).

Published index (what the app downloads, one file for all apps, cached with ETag):

```json
{ "schemaVersion": 1, "generatedAt": "2026-10-25T12:00:00Z", "apps": { "com.microsoft.teams2": [ { "id": "c_01HZ...", "title": "Mic and camera toggles", "rows": [ "...as above..." ] } ] } }
```

Why one index file: the app downloads the whole index, so a request never names an app. The server then learns nothing about which apps a user has. This works while the index stays small, which is realistic for a small community. Revisit it if the index grows large.

Where the data lives:
- Bundled: the presets from `app-presets.md`. These are the owner's own, reviewed entries.
- Fetched from a server: community entries only. Phase 0 uses the GitHub raw URL. Phase 2 uses a Worker endpoint.

Validation rules (shared by CI and the server):
- `bundleID` matches `^[A-Za-z0-9.-]{3,200}$`, and every row's `app` equals `bundleID`.
- At most 20 rows, and at most 16 KB in total.
- `trigger.button` is 1 to 5. `duration` is `click` or `hold`. `level` is 1 to 3.
- Effect type is `keyboardShortcut` only. `keycode` is 0 to 127. `flags` uses only the bits in 0x1E0000 (Command, Shift, Control, Option).
- Denylist: Command+Q (keycode 12, flags 1048576), Command+Shift+Q (keycode 12, flags 1179648), and force quit (Command+Option+Escape). Any row that matches is rejected.
- No free-text fields. Titles come from a fixed list.

## 5. User experience

Settings (General or Buttons tab, a new "Community" section):
- Two separate switches, both off by default. "Show community setups" and "Share my setups".
- A "Delete my shared setups" button, which is visible once anything has been shared.

Downloading (switch 1 on):
1. In an app tab, the user clicks a new "Community setups" button. A popover lists the titles for that app, from the cached index.
2. Choosing a title shows its rows in plain text. "Add to this tab" writes the rows in the same way as a preset (checkboxes, conflict handling, undo).
3. If the index cannot be loaded, the popover says so, and the app keeps working with its own rows.

Sharing (switch 2 on):
1. In an app tab with rows, the tab's context menu (the existing menu on the app strip) has "Share this tab...".
2. A sheet shows the exact JSON that would be sent, and a short statement: what is sent, that it is public, and how to delete it.
3. "Send" uploads it. "Cancel" sends nothing. The sheet shows the result, including the record ID.
4. Shared setups are listed under Settings, each with "Delete".

Withdrawing: turning off "Share my setups" stops uploads at once. "Delete my shared setups" sends a delete request for each record. If the server cannot be reached, the app keeps the requests and retries at the next launch.

## 6. Technical design

Options compared. Costs are from the sources above. "Owner runs" means what you would need to operate.

| | GitHub repo + PRs + CI | Cloudflare Worker + D1 | Supabase | CloudKit |
|---|---|---|---|---|
| Cost at small scale | Free (public repo, standard runners) | Free tier covers small use; $5/month minimum on paid plan | Free tier with 500 MB and pausing after 1 week of inactivity; $25/month for Pro | No per-request price shown; developer program likely required (not verified) |
| In-app upload | No. Users need a GitHub account and a pull request, or a pre-filled issue link | Yes, with a POST endpoint | Yes, with an API and row-level security | Yes, using the app's iCloud container |
| Abuse handling | Pull-request review; GitHub account friction deters spam | Rate limiting per IP hash, bot check (Turnstile, not verified), size and schema limits | Row-level security, rate limits, bot check (not verified) | Limited to Apple's tooling; no custom rate limiting verified |
| Moderation | Human review of every pull request | Admin endpoint, moderation queue (you build it) | Admin tools in the dashboard, or a queue you build | CloudKit Dashboard; no moderation UI verified |
| GDPR | Contributor's GitHub handle is public personal data; history cannot be fully erased | Needs a data processing agreement; EU data location not verified | Needs a data processing agreement; EU region not verified | Apple is the processor; EU data location not stated; EU terms exist for EU-enrolled organizations |
| Owner runs | Repo, CI, review time | Worker code, D1 schema, moderation, backups, monitoring | Project, SQL, policies, admin, pausing risk | Little infrastructure; Apple runs it; less control |

Recommendation: Phase 0 uses the GitHub repository, with no in-app upload. Phase 2, if demand appears, uses a Cloudflare Worker with D1 for anonymous submissions. Supabase is the fallback if you want built-in auth and an admin dashboard. CloudKit is not recommended now: its quotas and data location are not verified, its moderation tools are limited, and it ties the feature to Apple's terms.

New code (phase 2 only):
- `App/Community/CommunityIndex.swift`: download with ETag, cache, schema check, ignore unknown `schemaVersion`.
- `App/Community/SubmissionBuilder.swift`: builds the JSON from one app tab's rows only. It copies the allowed keys and nothing else.
- `App/Community/ConsentStore.swift`: stores the two switches and the consent text version, in the config under a new `Community` key.
- `App/Community/DeleteSecretStore.swift`: stores the random delete secret in the Keychain, one per record.
- Worker (separate repository): `POST /v1/submissions`, `GET /v1/index` (cached one hour), `POST /v1/delete`, and an admin route behind access control.

Changed: `ButtonTabController.swift` (Community setups button and sharing sheet), `AppTabStripView.swift` (Share this tab menu item), `Config.m` and `ConfigReadme.md` (version bump and migration for the `Community` key).
Unchanged: the helper, which must keep doing no networking, and the remap matching and row format.

Risks:
- Config leak. A bug that uploads the whole config would expose the device-linked license hash. Mitigation: the builder copies allowed keys only, and a unit test fails if `License`, `State` or any key outside `Remaps` appears in a submission.
- Consent mistakes. Sharing must be impossible while the switch is off. Mitigation: a test that calls the upload path with the switch off and expects zero requests.
- Data protection on app names. A bundle ID of a health, dating, religious or political app can reveal special-category data (Article 9). Mitigation: decision 6.
- Abuse: spam records, fake bundle IDs, and harmful shortcut sets. Mitigation: the validator, denylist, review queue and rate limits.
- Helper reload after applying a community setup. It uses the same `commitConfig()` path as presets, which is already in use.
- Maintenance: moderation time grows with each submission.

## 7. Privacy and legal

Scope note: this is an analysis for you to check with a qualified lawyer, not legal advice.

Data that would be collected:
- Submission content: the bundle ID and the button rows. Not personal data by itself, but it can become personal data when combined with an identifier or with an IP address, and when it reveals special-category data (Article 9).
- Delete secret: a random value held on the device. Only its hash is stored on the server. The hash is not personal data on its own, but it links one record to one device.
- IP addresses (visible to the host, present in server logs and rate-limit counters): personal data. Submission time and app version: low risk, but personal data when linked to a device.

Consent (GDPR Article 6(1)(a), with Article 7 conditions):
- Consent must be specific, freely given, and as easy to withdraw as to give (Article 7(3)). Your current model, where access to community setups depends on sharing, risks failing "freely given" (Article 7(4)). Recommendation: two separate switches, as in section 5, with access to downloads not depending on sharing.
- Draft consent text, for sharing (plain English, to be checked and translated):
  "Share this app tab's button settings. The shared setup contains only the app's bundle ID and the buttons I chose. It never contains my license, my device details or my other settings. The setup is public and can be downloaded by other users. I can delete it at any time in Settings. Withdrawing my consent stops future sharing. It does not undo sharing that already happened, but deleting my setups removes them from the server."
- Draft consent text, for downloads: "Show setups that other users shared. Downloading does not send the names of my apps. My IP address is visible to the host, as with any website."
- Article 7(3) requires the user to be informed before giving consent. A privacy notice (Article 13) must name the controller, the host, the retention periods and the rights. Both must be in place before the switch is shown.

Retention and deletion:
- Shared records: kept until the user deletes them. Question for you: should they also expire automatically after a set period, for example 12 months?
- Server logs: short. Question for you: 7 days or 30 days? Confirm the provider's log retention first, which was not verified.
- Rate-limit counters: hashed IPs, expire within one day.
- Deletion: through the delete secret in the app, which needs no e-mail address. Deleting the record and the index entry (within 24 hours, when the index cache expires) supports the erasure right in Article 17.

Limits that cannot be removed: the GitHub history keeps every change unless it is rewritten, and cached index copies on other users' Macs cannot be erased. Do not use GitHub for personal data you may need to erase. Tell users both points in the consent text.

Transfers and processors:
- GitHub, Cloudflare, Supabase and Apple are US companies. Check each provider's data processing agreement and EU-US Data Privacy Framework status. Not verified in this research.
- Question for you: whether a data protection impact assessment (Article 35) is needed. It is probably not for a small, non-profiling service, but check.

Controller and employer:
- Question for you: you use a dedalus.eu account. Who is the controller for a public service that collects user data, you personally or your employer? Check the employer's policies and get approval before phase 2. This matters more than any other item in this section.

Licensing:
- MMF License: a server and community feature is additional code. The license's monetization clauses still apply if you ever charge for the app. Question for you: does a separate server count as part of "Your Source"?
- Contributed content: a contributor needs terms for what the project may do with the setup. Question for you: which license should shared setups carry? Options: CC0 (simplest, no attribution), CC BY 4.0 (attribution required), or only the service terms. Recommendation: CC0, since the content is short configuration data.

## 8. Phases and acceptance criteria

Phase 0: curated repository, no app change.
- A public repository holds the JSON schema, a set of 10 valid and 10 invalid fixture files, and a validator script.
- A GitHub Actions workflow runs the validator on every pull request, and fails on any invalid fixture.
- Pull requests need one approving review before merge.
- Repository README states that entries are public and cannot be fully erased from history.

Phase 1: read-only in the app.
- The app downloads the index with ETag, caches it, and works offline.
- A future `schemaVersion` is ignored with a short message, not a crash.
- Downloading sends no app name or bundle ID to the server. Checked by reading the request URL in a test.
- Adding a community setup gives the same rows as adding a preset.

Phase 2: opt-in sharing.
- Sharing is impossible while the switch is off. A unit test asserts zero requests with the switch off.
- The sheet shows the exact bytes that are sent. A test compares the preview with the request body.
- The builder never copies keys outside `Remaps`. A test fails if `License`, `State` or other keys appear.
- Delete removes the record and its index entry, and the index cache expires within 24 hours.
- Rate limiting rejects more than the agreed number of submissions from one hashed IP per day. Tested.
- The privacy notice is live before the switch is shown.
- The owner's employer check (section 7) is recorded as done.

Phase 3: operations.
- Moderation queue has a target response time, written down.
- Backups and log retention are configured and tested by a restore.
- Abuse reports are counted and shown to you.

## 9. Open decisions for the owner

1. Which backend do you start with?
   (a) GitHub repository only, with no in-app upload. (b) Cloudflare Worker with D1 now. (c) Supabase now.
   Recommendation: (a). Revisit (b) only when the repository shows steady demand.
2. Are downloading and sharing separate consents?
   (a) Yes, two switches, with downloads independent of sharing. (b) No, downloads require sharing, as in your original idea. (c) Downloads are on by default and sharing is off.
   Recommendation: (a). Option (b) conflicts with Article 7(4) and is the main legal risk here.
3. How are submissions identified?
   (a) Anonymous, with a delete secret kept on the device. (b) Tied to a GitHub or Apple login. (c) No deletion at all.
   Recommendation: (a). Option (b) adds personal data. Option (c) fails the erasure right.
4. How are submissions moderated?
   (a) Every submission is reviewed before it is published. (b) Automatic publication after validation, with a report button. (c) Only trusted contributors can publish.
   Recommendation: (a) while volume is low. Move to (b) only when the review queue is a burden.
5. How long are records and logs kept?
   (a) Records until deleted, logs 7 days. (b) Records expire after 12 months, logs 30 days. (c) Records until deleted, logs as short as the provider allows.
   Recommendation: (a) or (c). Confirm the provider's log retention first.
6. Are apps with sensitive purposes excluded?
   (a) Exclude a fixed list of categories (health, dating, religion, politics, union). (b) Allow, with a warning. (c) Allow everything.
   Recommendation: (a). A bundle ID can reveal special-category data.
7. Which license applies to shared setups?
   (a) CC0. (b) CC BY 4.0. (c) Only the service terms.
   Recommendation: (a), since the content is short configuration data.
8. Who is the controller, and is your employer's approval needed?
   (a) You personally, on a personal domain. (b) Your employer, with written approval. (c) Not yet decided.
   Recommendation: resolve this before phase 2, through your employer's compliance process if needed.

## 10. Sources

- GitHub Docs, GitHub Actions billing: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- Cloudflare Workers pricing: https://developers.cloudflare.com/workers/platform/pricing/
- Cloudflare D1 pricing: https://developers.cloudflare.com/d1/platform/pricing/
- Supabase pricing: https://supabase.com/pricing
- Apple, CloudKit: https://developer.apple.com/icloud/cloudkit/
- Apple, CloudKit design guide (linked from the CloudKit page, not read): https://developer.apple.com/icloud/cloudkit/designing/
- Apple Developer Program License Agreement (search summary only): https://developer.apple.com/support/terms/apple-developer-program-license-agreement/
- GDPR Article 7 (unofficial text): https://gdpr-info.eu/art-7-gdpr/
- GDPR Article 9 (unofficial text): https://gdpr-info.eu/art-9-gdpr/
- Repository files: `Shared/Constants.h`, `Shared/Config/default_config.plist`, `Shared/Config/Config.m`, `Shared/Config/ConfigReadme.md`, `Helper/Core/Remap/Remap.m`, `License`
