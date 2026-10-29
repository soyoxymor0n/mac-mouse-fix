# Community setups Worker

A Cloudflare Worker with a D1 database. It receives setups that users share from the app ("Share this tab…") and keeps them in a review queue with status `pending`. Nothing is public until you copy a reviewed setup into the [setups repository](https://github.com/soyoxymor0n/mac-mouse-fix-setups) by hand.

Plan and decisions: `docs/features/community-sharing.md`.

## Routes

| Route | Body | Answer |
|---|---|---|
| `POST /submit` | A setup in the repository format (`schemaVersion`, `bundleID`, `title`, `rows`), at most 16 KB | `201 {"id", "deleteToken", "status": "pending", "license": "CC0-1.0"}`, or `413`, `415`, `400`, `422` |
| `POST /delete` | `{"id", "token"}` | `204`, or `404` when the ID and token don't match (it doesn't say which part was wrong) |
| anything else | | `404` (unknown path) or `405` (wrong method) |

`/submit` checks the same rules as the app and `scripts/validate.py`: schema version 1, a bundle ID that matches `[A-Za-z0-9.-]{3,200}`, a title from the fixed five, 1 to 20 rows, keycode 0 to 127, flags only in `0x1E0000`, effect type `keyboardShortcut` only, no Command+Q, Command+Shift+Q or Command+Option+Escape. Unlike the download, every row must pass. It also refuses apps with sensitive purposes (health, dating, religious, political, financial); the list is in `src/validate.js` and in `App/UI/Main/Tabs/ButtonTab/AppTabs/CommunitySharing.swift`. Extend both. `test/sync.test.js` fails if they differ.

## What is stored

One row per submission (`schema.sql`): a random ID, the status, the bundle ID, the title, the checked setup as JSON, the SHA-256 hash of the delete token, the creation time and the license `CC0-1.0`. The delete token itself is returned once to the app and never stored. The app keeps it in a file in its Application Support folder.

The Worker reads no IP address and no other header except `Content-Type` and `Content-Length`, and stores nothing about the sender. It writes no logs of its own, and `wrangler.toml` keeps Workers Logs off. Cloudflare still processes requests the way it does for any Worker (for example its own request metrics and security logs); this Worker keeps nothing beyond that default. Check Cloudflare's current documentation for what that default is.

Retention: a record stays until its delete token is used. Deleting a `pending` or `rejected` record removes the row. Deleting a `published` record sets its status to `delete_requested` and clears the setup JSON, so you know to remove the file from the setups repository; delete the row after that.

There is no rate limiting in the Worker, because it would need the IP address. If spam appears, add a Cloudflare rate limiting rule for the Worker's route in the dashboard.

## Owner steps to deploy

Run these from this folder (`tools/community-worker`). They need Node.js. Nothing else to install: `npx` fetches wrangler.

1. `npx wrangler login` — opens the browser to log in to your Cloudflare account.
2. `npx wrangler d1 create mmf-community` — creates the database. Copy the `database_id` it prints into `wrangler.toml`, in place of `REPLACE_WITH_THE_DATABASE_ID`. (The ID is not a secret, but keep it out of public commits if you prefer.)
3. `npx wrangler d1 execute mmf-community --remote --file schema.sql` — creates the table.
4. `npx wrangler deploy` — deploys the Worker. It prints the URL, for example `https://mmf-community.<your-subdomain>.workers.dev`.
5. Paste that URL, without a path and without a trailing slash, into `CommunitySharingEndpoint.workerURL` in `App/UI/Main/Tabs/ButtonTab/AppTabs/CommunitySharing.swift`, in place of `https://example.invalid/community`. Then build the app. Until you do this, the app shows sharing as unavailable and sends nothing.
6. Optional check: `curl -i -X POST https://<your URL>/nothing` should answer `404`.

If you rename the Worker or the database, change `name`, `database_name` and the commands above to match.

## Reviewing and publishing

List the queue:

```sh
npx wrangler d1 execute mmf-community --remote --command "SELECT id, bundle_id, title, created_at, submission FROM submissions WHERE status = 'pending' ORDER BY created_at"
```

To publish one: save its `submission` JSON as `setups/<bundleID>-<topic>.json` in the setups repository, open a pull request (CI runs `scripts/validate.py`), merge it, then mark the record:

```sh
npx wrangler d1 execute mmf-community --remote --command "UPDATE submissions SET status = 'published' WHERE id = 's_...'"
```

To reject one: `UPDATE submissions SET status = 'rejected' WHERE id = 's_...'`, or delete the row.

Deletion requests for published setups:

```sh
npx wrangler d1 execute mmf-community --remote --command "SELECT id, bundle_id, title FROM submissions WHERE status = 'delete_requested'"
```

Remove the file from the setups repository, then `DELETE FROM submissions WHERE id = 's_...'`.

## Tests

`node --test test/` (from this folder) or `node --test tools/community-worker/test/` (from the repository root). The tests use an in-memory stand-in for D1 and make no network requests.
