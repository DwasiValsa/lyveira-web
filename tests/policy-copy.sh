#!/usr/bin/env bash
#
# Copy gate for lyveira.app.
#
# This site is plain HTML with no build step and no package.json, so there is
# nothing to hang a test runner off — this script IS the test suite. It asserts
# the legal and store-facing copy that an App Review or Play Policy reviewer
# reads, and it walks every internal link so a renamed directory cannot 404 in
# production.
#
# `set -e` is deliberately omitted. A gate that stops at the first failure hides
# every failure below it, which is how this workspace ran for a year with
# Terraform fmt, Checkov, Helm lint and YAML validation never executing at all.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=()
checks=0

fail() { failures+=("$1"); }

must_exist() {
  local path="$1"
  checks=$((checks + 1))
  [ -e "$ROOT/$path" ] || fail "$path: does not exist"
}

must_contain() {
  local path="$1" needle="$2"
  checks=$((checks + 1))
  if [ ! -f "$ROOT/$path" ]; then
    fail "$path: does not exist (wanted to find \"$needle\")"
    return
  fi
  grep -qF -- "$needle" "$ROOT/$path" || fail "$path: missing \"$needle\""
}

must_not_contain() {
  local path="$1" needle="$2"
  checks=$((checks + 1))
  if [ ! -f "$ROOT/$path" ]; then
    fail "$path: does not exist (wanted to ban \"$needle\")"
    return
  fi
  if grep -qF -- "$needle" "$ROOT/$path"; then
    fail "$path: still contains banned \"$needle\""
  fi
}

# Whole-line match. `must_contain .assetsignore 'tests'` was satisfied by
# `#tests` — i.e. by the exact edit that disables the line — so a guard on a
# config directive has to pin the directive, not a substring of it.
must_contain_line() {
  local path="$1" line="$2"
  checks=$((checks + 1))
  if [ ! -f "$ROOT/$path" ]; then
    fail "$path: does not exist (wanted the line \"$line\")"
    return
  fi
  grep -qxF -- "$line" "$ROOT/$path" || fail "$path: missing the exact line \"$line\""
}

# Site-wide ban. A claim corrected on one page and left standing on four
# others is still a false claim; pinning it per-page means the next new page
# starts unguarded.
must_not_contain_any_html() {
  local needle="$1" file hits=""
  checks=$((checks + 1))
  while IFS= read -r file; do
    if grep -qF -- "$needle" "$file"; then
      hits="$hits ${file#"$ROOT"/}"
    fi
  done < <(html_files)
  [ -z "$hits" ] || fail "banned claim \"$needle\" appears in:$hits"
}

# The published page set. `.wrangler/` is a local build cache that is not
# deployed; leaving it in made the gate non-hermetic — it could fail on a
# developer's machine and pass in CI, which is how a gate stops being trusted.
html_files() {
  find "$ROOT" -name '*.html' \
    -not -path "$ROOT/.git/*" \
    -not -path "$ROOT/.wrangler/*" | sort
}

# Every internal href must resolve on disk. This is the check that catches the
# 404 class — a store console pointed at a URL this site does not serve.
check_links() {
  local file dir href target
  while IFS= read -r file; do
    dir="$(dirname "$file")"
    while IFS= read -r href; do
      href="${href#href=\"}"
      href="${href%\"}"
      case "$href" in
        mailto:*|http://*|https://*|tel:*|\#*) continue ;;
      esac
      href="${href%%\#*}"   # drop the fragment
      href="${href%%\?*}"   # drop the query
      [ -n "$href" ] || continue
      case "$href" in
        /*) target="$ROOT$href" ;;
        *)  target="$dir/$href" ;;
      esac
      checks=$((checks + 1))
      case "$href" in
        */) [ -f "${target}index.html" ] || fail "${file#"$ROOT"/}: href=\"$href\" has no index.html" ;;
        *)  [ -f "$target" ]             || fail "${file#"$ROOT"/}: href=\"$href\" does not resolve" ;;
      esac
    done < <(grep -oh 'href="[^"]*"' "$file")
  done < <(html_files)
}

# Every redirect TARGET must resolve on disk too. Checking only that the string
# "/privacy-policy" appears in _redirects let a mutation repoint it at /nope/
# and stay green — which is the one thing the file exists to prevent.
check_redirects() {
  local from to code target
  [ -f "$ROOT/_redirects" ] || { fail "_redirects: does not exist"; return; }
  while read -r from to code _rest; do
    case "$from" in ''|\#*) continue ;; esac
    checks=$((checks + 1))
    [ -n "$to" ] || { fail "_redirects: \"$from\" has no target"; continue; }
    case "$code" in
      30[12378]) ;;
      *) fail "_redirects: \"$from\" has status \"$code\", not a redirect code" ;;
    esac
    case "$to" in
      http://*|https://*) continue ;;
    esac
    target="$ROOT${to%%\#*}"
    case "$to" in
      */) [ -f "${target}index.html" ] || fail "_redirects: \"$from\" points at \"$to\", which has no index.html" ;;
      *)  [ -f "$target" ]             || fail "_redirects: \"$from\" points at \"$to\", which does not resolve" ;;
    esac
  done < "$ROOT/_redirects"
}

# ── Assertions ──────────────────────────────────────────────────────────────

check_links
check_redirects

# ── The gate gates the deploy ───────────────────────────────────────────────
# Dropping either of these is today's wrong behaviour: a deploy that publishes
# whatever is on main without reading this file. `continue-on-error` is banned
# outright: with it on the gate step, `needs: [test]` is satisfied by a job
# that failed, so both assertions above would still pass while nothing blocks.
must_contain .github/workflows/deploy.yml 'needs: [test]'
must_contain .github/workflows/deploy.yml 'bash tests/policy-copy.sh'
must_not_contain .github/workflows/deploy.yml 'continue-on-error'
# Everything in the project root is uploaded to Pages and served, so this
# script would otherwise be public at /tests/policy-copy.sh. Whole-line, because
# `#tests` contains "tests" and is exactly how you switch the rule off.
must_contain_line .assetsignore 'tests'

# ── FIX 3: Play's deletion URL must work without the app ────────────────────
# Pinned as whole lines, not fragments. A 1-line stub holding only the five
# asserted phrases passed the first version of this gate — everything that
# makes the page an actual deletion route (the email path, what is erased,
# what is kept, the subscription warning) was unguarded.
must_exist delete-data/index.html
must_contain delete-data/index.html 'Privacy Settings'
must_contain delete-data/index.html 'Delete all my data'
must_contain delete-data/index.html 'You do not need the app installed'
must_contain delete-data/index.html 'support@lyveira.app'
must_contain delete-data/index.html 'Export My Data'
must_contain delete-data/index.html '<h2>In the app</h2>'
must_contain delete-data/index.html '<h2>By email, without the app</h2>'
must_contain delete-data/index.html '<h2>What gets deleted</h2>'
must_contain delete-data/index.html '<h2>What we keep, and for how long</h2>'
must_contain delete-data/index.html '<h2>Subscriptions are separate</h2>'
must_contain delete-data/index.html '<li>Your mood logs, journal entries, and voice-journal transcripts.</li>'
must_contain delete-data/index.html '<li>Your safety plan and any crisis-screen records.</li>'
must_contain delete-data/index.html '<li>Your AI Coach conversations and everything the coach remembered about you.</li>'
must_contain delete-data/index.html '<li>Your financial records and Money &amp; Mood history.</li>'
must_contain delete-data/index.html '<li>Your push tokens and habit reminders, so the notifications stop.</li>'
must_contain delete-data/index.html '<li>Any reports you sent us about AI responses.</li>'
must_contain delete-data/index.html 'Deleting your data does not cancel a paid subscription'

# A published retention period is a commitment, so every number on the page is
# pinned to something that sets it, and anything nobody could point at was
# removed rather than guessed:
#   Server logs 30 days  — dwasi-infra/terraform/phase8-ecs/main.tf:291
#                          (aws_cloudwatch_log_group.this retention_in_days = 30)
#   Backups up to 35 days — dwasi-infra/terraform/phase1/main.tf:45
#                          (backup_retention_days = 35), docs/OPERATIONS.md:198
# The email-hash figure was not merely unverified, it was WRONG: the dedup
# registry is permanent by design (dwasi-identity app/models/archive.py:58-67,
# "Never deleted — this is the compliance record") and archived_accounts keeps
# the encrypted email and display name with no purge job at all. A "30 days"
# that is really "forever" is the worst kind of published number, so the page
# now says indefinitely. Crash-report retention belongs to PostHog and nothing
# in this workspace sets it, so the page no longer names a period.
must_contain delete-data/index.html '<li><strong>Server logs &mdash; 30 days.</strong> These hold request metadata, not your content.</li>'
must_contain delete-data/index.html '<li><strong>Encrypted database backups &mdash; up to 35 days</strong>, for point-in-time restore.'
must_contain delete-data/index.html '<li><strong>A deletion record &mdash; kept indefinitely.</strong>'
must_not_contain delete-data/index.html 'hash of your email address &mdash; 30 days'
must_not_contain delete-data/index.html 'Crash reports &mdash; 90 days'

# ── FIX 1: the policy must say what is actually collected ───────────────────
# Play counts mental health under Health info, and this app collects mood,
# journal, coach conversations and crisis records. The old sentence denied it.
must_not_contain privacy/index.html 'We do not collect health data unless'
must_contain privacy/index.html 'Health-related information'
# Direction-sensitive. `must_contain 'Google Health Connect'` was satisfied by
# the exact opposite claim ("Lyveira reads your steps and sleep from Apple
# Health and Google Health Connect"), which would be an undeclared health-data
# read on both stores. HEALTHKIT is false in all four eas.json profiles.
must_contain privacy/index.html 'Lyveira does not read from Apple Health or Google Health Connect in this release.'
must_not_contain privacy/index.html 'Lyveira reads your steps'
# The journal is encrypted on both sides; the app's own copy was corrected
# first (profile/privacy.tsx: "Encrypted on this device and at rest on our
# servers") because the server holds the key and the coach decrypts for recall.
# Anchored to the whole <li>: the phrase alone also appears further down the
# page, so a bare substring check left the TL;DR bullet — the one line a
# reviewer actually reads — free to revert. A mutation caught that.
must_contain privacy/index.html '<li>Your journal entries are encrypted on your device and again on our servers.</li>'
must_not_contain privacy/index.html '<li>Your journal entries are encrypted on your device.</li>'
must_contain privacy/index.html '<li>Your mood logs, journal entries, AI Coach conversations, and crisis-screen records are health-related information'
# Expo relays every push via exp.host, and a habit reminder's title is a name
# the user typed (notification/app/scheduler.py: title=f"Time for: {habit}").
must_contain privacy/index.html 'Expo Application Services'
must_contain privacy/index.html 'relays every notification'
must_contain privacy/index.html 'habit name you typed'
must_contain privacy/index.html 'Google on Android'
# "Settings -> Delete Account" is a screen that does not exist, and the
# deletion path is exactly what a reviewer validates. The link to the no-app
# route is pinned too — deleting it left the gate green at one check FEWER,
# which is the failure mode of counting assertions instead of pinning them.
must_contain privacy/index.html 'Privacy Settings &rarr; Delete all my data'
must_contain privacy/index.html '<a href="../delete-data/">request deletion without the app</a>'
must_contain support/index.html '<a href="../delete-data/">request deletion without the app</a>'
must_not_contain privacy/index.html 'Settings &rarr; Delete Account'
must_not_contain privacy/index.html 'Payments and subscriptions (Apple, and RevenueCat'
# "We delete your personal data" is not the whole truth while identity keeps a
# permanent dedup row + an encrypted email/display-name archive with no purge
# job (dwasi-identity app/models/archive.py:58-67, app/services/archive_service.py).
# The policy has to say so itself, not only on /delete-data.
must_contain privacy/index.html 'One record outlives the deletion: a one-way hash of your email address, plus your email address and display name held in encrypted form, kept indefinitely'

# ── The Security section must describe the encryption that EXISTS ───────────
# This is the sentence that got it wrong in the opposite direction: a round of
# work whose whole point was to stop over-claiming encryption published
# "field-level encryption of journal and coach content on our servers". Coach
# transcripts are plaintext in a Text column and that is deliberate —
# dwasi-core-api app/models/coach_log.py:10 ("Privacy: content is plaintext
# (NOT encrypted at rest like journal entries)") and :55. What IS field-level
# encrypted is core-api's journal content (app/security/encryption.py,
# JOURNAL_ENCRYPTION_KEY) and agent-orchestrator's agent_memories.text
# (app/security/memory_encryption.py, AGENT_MEMORY_ENCRYPTION_KEY) — "what the
# coach remembers", which is not the same thing as the conversation.
# Pinned as the whole paragraph: every earlier survivor in this file was a
# reword walking past a substring, and this claim is the one a regulator reads.
must_contain privacy/index.html '<p>We use encryption in transit (TLS), encryption at rest on our database and storage, field-level encryption of your journal entries and of what the AI Coach remembers about you, on-device encryption of journal content, and access controls. Your AI Coach conversation transcripts are not field-level encrypted &mdash; they are protected by that at-rest encryption and by access controls, not by a separate key. No system is perfectly secure, but we work hard to protect your information.</p>'
must_not_contain_any_html 'field-level encryption of journal and coach content'
must_not_contain_any_html 'coach content on our servers'

# ── No page may claim the journal is encrypted ONLY on the device ───────────
# Server-side journal content is encrypted with a key WE hold, so "encrypted on
# your device" full-stop reads as end-to-end and is not true. It was corrected
# on privacy/ and support/ and left standing on the landing page's privacy FAQ,
# its feature card, features/ and about/. Banned site-wide so the next page
# starts guarded, and paired with a positive per page so deleting the
# corrective clause altogether also fails.
must_not_contain_any_html 'encrypted on your device.'
must_not_contain_any_html 'encrypted on your device<'
must_not_contain_any_html 'encrypted right on your phone'
must_contain index.html 'Your journal is encrypted on your device and again on our servers.'
must_contain index.html 'Journal entries are encrypted on your phone, and again on our servers.'
must_contain features/index.html 'every entry is encrypted on your device and again on our servers.'
must_contain about/index.html 'Your journal is encrypted on your device and again on our servers.'
# The hero stat sat next to a policy saying content is held server-side too.
must_not_contain index.html 'private — encrypted on device'

# ── "end-to-end" is never true here, in any spelling ────────────────────────
# The three bans above pin three exact SPELLINGS, so rewording to "encrypted
# end-to-end on your device" walked straight past all of them and past the
# positives, which match a different sentence. End-to-end means we could not
# read it even if compelled; we hold the server-side key, so no page may say it
# in any form. Nothing on the site uses the phrase today, so this bans a claim
# rather than guarding one.
must_not_contain_any_html 'end-to-end'
must_not_contain_any_html 'end to end'

# ── The journal-encryption claim appears THREE times on privacy/ ────────────
# The TL;DR bullet was pinned; the two body copies were not, so either could be
# reworded into a stronger claim with the gate green. Pin all three, because a
# reader who gets as far as "Content you create" or the health section is the
# reader deciding whether to trust us with a journal.
must_contain privacy/index.html 'Journal entries are encrypted on your device and again on our servers.</p>'
must_contain privacy/index.html 'and journal entries are encrypted on your device and again on our servers.'
must_contain index.html '<div class="l">ads — and your data is never sold</div>'

# ── FIX 2: these pages bill through Google Play too ─────────────────────────
# Substring bans cover all of pricing's "Apple Account settings" instances.
# "managed by Apple" rather than the one exact sentence: banning
# "Subscriptions are managed by Apple." left "Your subscription is managed by
# Apple." free to come back, and the cancel answer is the single most
# Play-reviewer-facing line on the site.
must_not_contain pricing/index.html 'Apple Account settings'
must_not_contain terms/index.html 'Apple Account'
must_not_contain_any_html 'managed by Apple'
must_contain support/index.html 'Google Play Store app'
must_contain support/index.html 'Payments &amp; subscriptions'
# Whole instruction, not fragments. Deleting pricing's Android steps outright
# stayed green because three other "Google Play account settings" strings on
# the page satisfied `must_contain pricing 'Google Play'`; and support's Play
# steps could be replaced with "Delete your Google account" while both of its
# asserted fragments still matched.
must_contain pricing/index.html '<details><summary>How do I cancel?</summary><p>Your subscription is managed by the store you bought it from. On iPhone: Settings → your name → Subscriptions → Lyveira → Cancel. On Android: Google Play Store app → your profile picture → Payments &amp; subscriptions → Subscriptions → Lyveira → Cancel subscription. Your Premium features stay until the end of the current period.</p></details>'
must_contain support/index.html '<p>On Android: open the <strong>Google Play Store app &rarr; your profile picture &rarr; Payments &amp; subscriptions &rarr; Subscriptions &rarr; Lyveira &rarr; Cancel subscription.</strong></p>'
must_contain support/index.html '<p>On iPhone: <strong>Settings &rarr; [your name] &rarr; Subscriptions &rarr; Lyveira &rarr; Cancel Subscription.</strong></p>'
# Each terms bullet pinned separately: `Google Play account (Android)` appears
# on two of them, so one assertion was covering both and neither was pinned.
must_contain terms/index.html '<li>Payment is charged to your App Store account (iOS) or Google Play account (Android) at confirmation of purchase.</li>'
must_contain terms/index.html '<li>You can manage or cancel anytime in your App Store account (iOS) or Google Play account (Android) settings.</li>'
must_contain terms/index.html 'Refunds are handled by Apple or Google'
# Support's deletion answer named the same non-existent screen as the policy.
must_not_contain support/index.html 'Settings &rarr; Delete Account'
must_contain support/index.html 'Privacy Settings &rarr; Delete all my data'
must_contain support/index.html 'and again at rest on our servers'

# ── Store-console URLs resolve ──────────────────────────────────────────────
# The App Store and Play consoles hold https://lyveira.app/privacy-policy, but
# the directory on disk is privacy/. Cloudflare Pages serves the redirect.
# check_redirects above proves each target resolves; these pin the two rules
# themselves, so neither can simply be dropped.
must_exist _redirects
must_contain_line _redirects '/privacy-policy   /privacy/       301'
must_contain_line _redirects '/delete-account   /delete-data/   301'


# ── Report ──────────────────────────────────────────────────────────────────

if [ ${#failures[@]} -gt 0 ]; then
  echo "policy-copy: ${#failures[@]} failure(s) of $checks checks"
  for f in "${failures[@]}"; do
    echo "  FAIL  $f"
  done
  exit 1
fi

echo "policy-copy: $checks checks passed"
