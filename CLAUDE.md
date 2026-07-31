# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single Ruby script that deletes a Bluesky account's own posts older than a configurable
number of days, run on a schedule via GitHub Actions. There is no build system, package
manager, or test suite — the entire application is `delete_posts.rb`.

Motivation (from README): the author uses Bluesky mainly as a "safety check" presence rather
than for active branding, and considers it risky to leave old posts up that no longer reflect
current thinking, so old posts are pruned automatically.

## Running it

```bash
BSKY_HANDLE=your.handle BSKY_APP_PASSWORD=xxxx DAYS_TO_KEEP=30 ruby delete_posts.rb
```

- Requires Ruby (CI uses 3.3) and only standard library gems (`net/http`, `json`, `time`, `uri`) — no `Gemfile`/`bundle install` needed.
- `BSKY_APP_PASSWORD` must be a Bluesky **app password** (Settings → App Passwords), not the main account password.
- `DAYS_TO_KEEP` defaults to `30` if unset.
- No test suite or lint config exists in this repo.

## Architecture

`delete_posts.rb` is a linear script (no classes), structured as:

1. **Auth**: `login` calls `com.atproto.server.createSession` to get a session (`did` + `accessJwt`).
2. **Fetch**: `get_posts` paginates through `app.bsky.feed.getAuthorFeed` (100 at a time via `cursor`) to collect the full post history for the authenticated account.
3. **Filter + delete**: `main` computes a UTC cutoff (`Time.now.utc - DAYS_TO_KEEP days`), then for each post whose `record.createdAt` is older than the cutoff, calls `delete_post` (`com.atproto.repo.deleteRecord`) and logs it.

All HTTP calls go through the raw `Net::HTTP` helpers `post_json`/`get_json` against `BASE_URL = https://bsky.social/xrpc`. Note `delete_post` builds an authenticated request manually (a stray unauthenticated `post_json` call at the top of that method is dead code/unused).

## CI/scheduling (`.github/workflows/delete-old-posts.yml`)

- Trigger is `workflow_dispatch` only — there is deliberately no `schedule:` cron. Actual scheduling
  is done externally: a Cloudflare Workers cron job calls the GitHub API to dispatch this workflow.
  This avoids GitHub Actions' behavior of auto-disabling scheduled workflows after 60 days of no
  repository activity. When touching this workflow, keep the `workflow_dispatch` trigger intact and
  remember the actual cadence lives in the Cloudflare Workers config, not in this repo.
- Secrets required in the repo: `BSKY_HANDLE`, `BSKY_APP_PASSWORD`.
- `DAYS_TO_KEEP` is sourced from a repository **variable** (`vars.DAYS_TO_KEEP`), not hardcoded in the workflow — change the retention window via Settings → Secrets and variables → Actions → Variables, not by editing the YAML.
