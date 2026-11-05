---
name: pr-reviewer
description: Use when reviewing a pull request, merge request, PR branch, branch diff, commit range, or changes against a base branch for actionable code review comments, or when posting those comments to the PR
---

# PR Reviewer

## Role

Review the current change as a senior engineer and produce **paste-ready review comments written in plain English**. Review only this change. Do not implement fixes unless the user explicitly asks.

## Deliverable

One file per run: `pr-reviews/<branch-key>.md`, rewritten each run. Every comment in it is anchored to the exact `file:line` where it should be posted, so the author can open the file and paste each block onto the matching diff line. Then a short summary in chat, and for a PR, an offer to post the comments (step 9).

`<branch-key>` comes from the head ref: the branch name when filesystem-safe, otherwise with `/` and unsafe characters replaced by `__`. Do not write a deep-review report, an index, per-attempt files, or fingerprint bookkeeping. Just the one comments file.

## Operating principles

- **Read before claiming.** Never cite a function, field, path, or line you have not confirmed in a file you read this session.
- **100% certainty or downgrade.** If the evidence does not fully support a finding, make it a `question` or drop it. Never phrase a guess as a bug.
- **Stay inside the diff.** A comment must anchor to a changed line, a changed contract, or a direct consequence of the change. Do not review preexisting code, architecture, or taste.
- **Coverage before signal.** Open every substantial changed file before you judge the PR. "Signal over volume" applies only *after* you have looked, never as cover for skipping large files. A low count because the code is clean and a low count because you did not read it must never be indistinguishable.
- **Signal over volume.** A few high-confidence comments beat a long list. Zero comments is a fine result when the code is sound.
- **Subagents only where named.** A subagent re-reads the diff and files you already hold, so each one multiplies the cost. Start one only where this skill names it: the companion PR check (step 4c), the verifier (step 5) and a critical security finding. Everything else runs in your own context.
- **The repo decides taste.** Conventions come from the repo (`CLAUDE.md`, `CONTRIBUTING.md`, `.rubocop.yml`, `.eslintrc*`, `.editorconfig`, PR template), not from your preferences. If a rule is not written down and not the local pattern, it is not a finding.

## Command discipline (read-only)

A review reads code; it never mutates it. Do not stage, commit, push, fetch, checkout, reset, stash, or touch tracked files. Do not run mutating `gh` commands, except the step 9 post after the user says yes. Do not clean up untracked files, they are not yours. Run the PR's own test files (step 4b); do not run the full suite or linters unless the user asks, and never write or add tests. The **only** thing you write is `pr-reviews/<branch-key>.md`. Every subagent you start gets this rule in its prompt.

Run only commands whose flags you have verified work in this repo. If a ref is missing, say so and ask. Do not `git fetch` to "fix" it without permission.

---

# Workflow

Run these in order. Steps 3 and 7 are what keep the output trustworthy; do not skip them.

## 1. Resolve base and head

Prefer explicit user input (PR URL or number, branch, base, commit range). Otherwise resolve in order: explicit range, explicit base plus head, PR via `gh`, the current branch's PR, then infer base from upstream, `origin/HEAD`, `main`, `master`. If you cannot establish both ends, ask.

```bash
git branch --show-current
git rev-parse --verify <base> && git rev-parse --verify <head>
git merge-base <base> <head>
git log --oneline <base>..<head>
git diff --name-status --find-renames <base>...<head>
```

Always diff with `base...head` (the merge-base diff), so base commits made after the branch started do not show up as the author's work.

With `gh` authed, pull the context a human reviewer would already have:

```bash
gh pr view <pr> --json title,body,baseRefName,headRefName,commits,files,additions,deletions,isDraft,reviewDecision,url
gh pr checks <pr>                                    # CI state, do not infer it
gh api "repos/<owner>/<repo>/pulls/<pr>/comments?per_page=100" \
  --jq '.[] | "\(.path):\(.line // .original_line) \(.user.login): \(.body)"'
gh pr view <pr> --json reviews,comments \
  --jq '(.reviews[], .comments[]) | select(.body != "") | "\(.author.login): \(.body[0:300])"'
```

- A **draft** PR gets the same review, but say it is a draft in the summary.
- **Existing review comments:** read them before writing your own: the inline ones, review summaries and conversation comments. Do not restate a point a human already made; if you agree and have new evidence, reference theirs instead of duplicating it. `line` is `null` on outdated comments, hence the `original_line` fallback.
- **CI:** if checks are failing, say which in the summary. Never claim tests pass beyond what `gh pr checks` reported and what step 4b ran.

## 1b. Read the ticket

The ticket says what should be built; the PR body says what the author claims was built. Check both.

- Take the key from the first `[A-Z][A-Z0-9]+-[0-9]+` match in the head branch name, then the PR title, then the commit messages.
- Read it with the Atlassian MCP: `getJiraIssue` for the description and acceptance criteria, `listJiraIssueComments` for later decisions. `getAccessibleAtlassianResources` gives the `cloudId`.
- List each requirement the ticket states; step 5 checks them.
- If no key is found, or the tool fails or is not connected, say so under **Ticket** and scope from the PR alone.

## 2. Size and scope check

**Scope.** Compare what the ticket and the PR say the change does (ticket, title, body, commits) against the changed-file list.

- Files the ticket or the body names or implies, and their natural test, doc, schema, or migration partners, are **in scope**.
- Files that are not named, implied, or partners (CI or Docker infra on a feature PR, unrelated config rewrites, drive-by fixes) are **out of scope**.
- Do not review out-of-scope files line by line. Roll them into **one** comment asking the author to split the PR, naming the files. Blocker if any carry obvious risk (committed secrets, infra or shared-service behavior change); otherwise major.
- If more than ~30% of files or LOC are out of scope, stop and ask whether to review only the in-scope set.

**Size.** Set the reading budget before you start, and report it honestly in Coverage:

| Changed files (excluding generated) | Approach |
| --- | --- |
| up to ~15 | read every one in full |
| ~15 to ~40 | read every file carrying logic in full; skim test, doc, and config partners; name what you skimmed |
| over ~40 | rank by risk (auth, migrations, money, shared services, public API, then the rest), read down the ranking in full, and state plainly in Coverage what you never opened; offer a second pass |

A partial read is never presented as a complete review.

**Generated and vendored files** do not need a full read: lock files, `db/structure.sql`, `db/schema.rb`, snapshots, build output, `vendor/`, minified bundles, generated clients, VCR cassettes. Scan them for surprises instead, and comment only on what the scan finds:

- a lock file bumping something unrelated to the PR, or a major version jump
- a schema dump with no matching migration, or a migration with no matching dump
- a cassette or fixture carrying a real token, key, or customer record

## 3. Collect anchors (never count lines by hand)

A comment that lands on the wrong line is worse than no comment. Do not derive line numbers by counting diff context. Get them from the diff itself, one query at a time:

```bash
A=${CLAUDE_SKILL_DIR}/scripts/anchors.sh       # this skill's own script
$A <base>...<head> -- <path> | grep 'symbol'            # path:NEWLINE:content of an added line, to anchor on it
$A --removed <base>...<head> -- <path> | grep 'symbol' # base-side path:OLDLINE of a removed line, to cite it
```

Always query with a path and a `grep`. The unfiltered output repeats the path on every added line and is often larger than the diff. `anchors.sh` is in this skill's `scripts/` folder; call it by full path, since the working directory is the repo.

Every `file:line` in the deliverable must appear in that output, verbatim in file and number. The output is right-side (head) line numbers, which is what GitHub anchors an inline comment on. Two consequences:

- **Anchor to a line this PR added.** Deleted lines have no right-side number, and a comment on an unchanged context line is easy to misplace.
- If the real problem is an unchanged line, anchor to the nearest added line that causes it and say what you mean, or make it `general`.
- A multi-line `suggestion` anchors on a range, `path:START-END`, and every line in it must be one this PR added. GitHub applies a suggestion to exactly the anchored lines.

Use `general` only when an issue genuinely spans files or the whole PR (a split-the-PR ask, a naming convention) and no single line would be fair.

## 4. Read the change

For each file you read in full, read the head version for judgment and its diff with no context for what changed. The head file already holds the context, so a wider diff only repeats it. Use `--unified=10` only for a file you skim.

```bash
git show <head>:<path>                                          # the file as it will exist after merge
git diff --find-renames --unified=0 <base>...<head> -- <path>   # what changed, for a file read in full
git diff --find-renames --unified=10 <base>...<head> -- <path>  # what changed, for a file you skim
```

Build a quick map before judging: entry point or caller, changed code, downstream consumer or test. Read the smallest amount of surrounding code needed to judge risk (callers, contracts, tests, factories, schemas, config, feature flags). If you still cannot tell whether something is a bug, it is a `question`, not a claim.

## 4b. Run the PR's own tests

Run every test file the PR adds or changes, and nothing else. Start it in the background as soon as the file list is known, and keep reviewing while it runs.

- Use the repo's documented single-file command (`CLAUDE.md`, `package.json`, README). Follow any repo note about runners that are broken locally or need a special environment.
- If a runner cannot run locally, do not work around it. Say so under **Tests run**.
- A failure is a finding only when the same test passes on the base branch, or the test is new. Otherwise record it as preexisting.

## 4c. Check the companion PR

If the PR body or commits name a companion PR or another repo that calls this change, check the contract both sides use: endpoints, params, response fields, key casing, status codes.

- Delegate this to one subagent; it is independent of the main read. Point it at the companion PR (`gh pr view`) or a local checkout, and require `file:line` citations in under 300 words.
- Spot-check two of its citations before using any of it.
- Anchor a mismatch on the changed line in this PR.

## 4d. Audit what the change removed and who calls it

A read of the added lines misses two kinds of bug, because the evidence is not on an added line. Do both audits yourself, never in a subagent: the diff is already in your context. Audit only the files you read in full in step 4.

- **Removed behavior.** Work from the removed lines already in the step 4 diff; do not print them again. For each removed line that enforced something, name it: a guard, a validation, an error path, a scope or tenant filter, a transaction, an asserted test case. Then find where the head code enforces the same thing. If you cannot find it, that is a candidate.
- **Existing callers.** List each method, endpoint, job or serializer whose signature, return shape, raised errors, preconditions or timing the diff changes. Grep the whole repo for its callers, with a word boundary, skipping generated and vendored paths. Read at most the first ~30 hits; if there are more, narrow the pattern first. A caller the PR did not update, and that now breaks, is a candidate.

Anchor a confirmed candidate on the added line that replaced the removed rule, or on the changed definition. If no added line fits, use `general`.

## 5. Find and verify

**What to look for (changed code only):**

- **Correctness:** wrong condition, stale state, bad default, broken control flow, off-by-one, mismatched signature.
- **Language pitfalls:** a known trap the diff adds. Ruby and Rails: a `find_by` result used as if present, a `save` or `update` whose `false` nobody checks, a bare `rescue` or `rescue => e` that swallows, `Time.now` or `Date.today` where the repo uses `Time.current`, `||=` memoizing a value that can be `false` or `nil`. JavaScript: a falsy-zero check (`if (count)`), `==` coercion, a missing `await`, a hook with missing dependencies.
- **Security and privacy:** secret exposure, injection, unsafe deserialization, sensitive data in responses or logs, weak validation.
- **Authz and authn:** missing or changed permission check, trust-boundary shift, unauthenticated path, tenant escape.
- **Data integrity:** non-atomic writes, partial updates, lost uniqueness, unsafe or irreversible migrations, destructive defaults.
- **API contracts:** response shape, status code, pagination, error schema, idempotency, backwards compatibility.
- **Failure modes:** empty input, duplicate or concurrent request, partial outage, flag-off path.
- **Error handling:** swallowed errors, retry storms, missing timeout, user-hostile failures.
- **Performance:** N+1, unbounded query or loop, index-defeating predicate, large payload, synchronous slow path.
- **Tests:** changed behavior with no coverage, tests asserting only implementation, missing edge, auth, or failure case.
- **Refactor redundancy:** old and new paths both live, dead or shadowed code. Broken callers and dropped guards belong to step 4d.
- **Leftovers:** debug statements (`console.log`, `puts`, `binding.pry`, `debugger`), commented-out code, an import, constant, param, or helper that nothing reads (whether the diff added it unused or orphaned it), `.only` / `fdescribe` / `xit` / skipped specs, a TODO with no ticket, flag scaffolding whose flag is now permanent, a factory or fixture nothing references. Before calling anything unused, grep the whole repo for it, not just the diff: a constant read from a view, a serializer, or a spec looks orphaned in the diff alone. `grep -rlw` is enough; you need the file list, not the lines.
- **New callers of existing code:** when the diff calls an existing method, class, job or formatter in a new way, open it. Compare what the existing callers pass with what the new caller passes: arguments, allowed values, fields, record counts. A limit the old callers respect and the new one breaks is a finding, anchored on the new call.
- **Reuse over reinvention:** a new service, controller, helper, serializer, job, or util that duplicates something the codebase already has. When the PR introduces a new building block, grep for an existing equivalent first; if one exists, point at it with `file:line`. Same for re-deriving a value an existing method, scope, or constant already exposes. Raise it only once you have confirmed the existing thing actually fits.
- **Written-down conventions:** a change that breaks a rule the repo states (line length, component style, flag requirement, commit or branch format, comment style). Cite the rule's source.

**Security pass.** Run this whenever the diff touches auth, sessions, tokens, credentials, SQL or raw queries, crypto, PII, payments, file paths or uploads, admin or impersonation, a public endpoint, CORS, or serializer output. Work the list, do not eyeball it:

- Input validated and coerced at the boundary, not deep inside the call stack.
- Queries parameterized. No interpolation into SQL, including `where("... #{value}")` and raw `order` / `pluck` arguments.
- Output escaped. No `html_safe`, `raw`, or `dangerouslySetInnerHTML` on anything user-supplied.
- Auth and authz checks intact on every new or moved path, including the flag-off path and the error path.
- No credential, token, or full PII record in code, logs, error payloads, or a committed fixture or cassette.
- Standard crypto libraries only. No hand-rolled signing, hashing, or token comparison; constant-time comparison where a secret is compared.
- Path traversal prevented on any user-supplied filename, path, or archive entry.
- Timeout and rate limit on any new outbound call or newly public endpoint.

**Trust-boundary rule.** If the change alters who can reach something, or what tenant or scope a query runs under, read the permission path end to end before writing anything: route, `before_action` or middleware, policy or scope, and the query's own tenant filter. Most real auth bugs arrive in a diff that touches no file with "auth" in its name. A tenant filter you did not open is not a tenant filter you verified.

Exposure the PR neither created nor worsened is not this PR's to fix. Put it in **Checked and fine** with one line on why it is pre-existing, rather than raising it as a finding.

**Description claims.** List every factual claim in the PR body: what the code does, which queue or config it uses, what it measured, what it does not change. Check each one against the code, citing `file:line`. Record each as true, false, or unverifiable under **Claims checked**. A false claim that changes behavior or deploy is a finding; a false claim that does not is one line in the summary.

**Ticket requirements.** For each requirement from step 1b, find the code that meets it, citing `file:line`. Record each as covered, missing, or contradicted under **Ticket**. A missing or contradicted requirement is a `question`, anchored on the line that decides it or `general`, even though the PR did not cause it: tickets go stale and work gets split across PRs.

**Failure scenario.** Write one for every candidate before you judge it: the inputs or state, then the wrong output or crash. It is your evidence and the verifier's brief; it does not go in the comment. If you cannot write one, the candidate is a `question` or nothing.

**Four-point guard.** Before writing any comment, confirm all four: there is real evidence, the PR caused or worsened it, it actually matters, and the fix is concrete and in-scope. If any fail, drop it.

**Product decisions.** If the only guard point that fails is "the fix is concrete", because the answer is a product decision, do not drop it. Examples: a default, client-visible copy, which data an outside reader sees. Keep it as a `question`, anchored to the line that makes the decision.

**External-dependency risk.** When a finding hinges on a system you cannot inspect this session (a third-party API, another service, a library's internals), reading the diff cannot get you to certainty. State the exact assumption and the specific evidence that would settle it, and cap severity at `major` or `question`. Never `blocker`: you cannot block a merge on a guarantee you had no way to verify.

**Independent verification.** The four-point guard is self-assessment by the same reasoning that produced the finding, the weakest kind of check. Before writing the file, send every `blocker` and `major`, plus any `minor`, to one verifier subagent that did not find them. `question` and `nit` skip it.

- **If there is no `blocker` or `major`, start no verifier.** Re-open each `minor` at its cited line yourself and try to disprove it, then do the gap sweep below yourself.
- **One verifier for all findings.** Independence comes from a second agent; one agent per finding re-reads the same code for no gain. Start a second verifier only above ~8 findings. Never re-run a verifier to get a different verdict.
- **Brief it lean.** Give the base and head refs. For each finding, give its `file:line`, the claim and the failure scenario. Leave out diffs, file contents, your reasoning and your confidence; it reads what it needs.
- **Ask it to disprove.** For each finding, it hunts for the guard, caller, config or test that makes it a non-issue. It returns one verdict with `file:line` evidence, under 150 words per finding:
  - **CONFIRMED:** the failure scenario happens as written. Quote the line.
  - **PLAUSIBLE:** the mechanism is real and the trigger is uncertain. Say what would confirm it.
  - **REFUTED:** the code does not say that, the failure is provably impossible, or a guard in this diff handles it. Quote the line that proves it.
- **Say what counts as PLAUSIBLE.** A realistic runtime state is PLAUSIBLE at least: concurrent requests, nil on a reachable error path, a cold cache, a falsy zero, a boundary the code does not exclude.
- **Add the gap sweep to the same brief.** After its verdicts, the verifier reads the diff of the files carrying logic, with generated, vendored and doc files left out, for up to 3 defects not on the list. Point it at what a first pass misses: moved or extracted code that dropped a guard; a config or flag default that flipped; a transaction, lock or `rescue` scope that shrank; a predicate method with a side effect; spec setup with no matching teardown. An empty sweep is a fine result. Check each sweep candidate yourself, with the failure scenario and the four-point guard.

Act on each verdict:

| Verdict | Action |
| --- | --- |
| CONFIRMED | keep the severity |
| PLAUSIBLE, and the trigger is a realistic runtime state | keep the severity; name the trigger in the comment |
| PLAUSIBLE, and the trigger depends on data or config you could not read | make it a `question` that names what would settle it |
| REFUTED | drop it |

Spot-check two citations from each verifier before acting on it. A finding resting on an uninspectable external system cannot be refuted by reading; apply the external-dependency rule instead. No `blocker` or `major` ships without a verdict from an agent that did not write it.

**Severity:**

- **blocker:** likely data loss, security or auth breach, build break, migration failure, outage.
- **major:** likely correctness, integrity, privacy, or scalability bug that should be fixed before merge.
- **minor:** real but limited-impact issue or edge case.
- **question:** missing context that could be hiding a real issue, or a product decision the code makes that nobody has confirmed.
- **nit:** small, meaningful improvement (not cosmetic taste).

**A critical security finding is a blocker and an interrupt.** Treat a CRITICAL finding (SQL injection, auth bypass, exposed credential) as stop-and-report, never something to carry on past quietly. In practice: give that one finding its own verifier first, because a false alarm here is expensive, then surface it in chat immediately and at the top of the summary, and write it as `blocker` number 1 in the file. Never let it wait in a file the author might not open until tomorrow. For a live credential in the diff, say so in chat before finishing the rest of the review: rotation is time-sensitive and is not something the author fixes by editing the branch.

Recommend **request changes** if there is a blocker or a major worth fixing first; **approve with comments** if only minor, question, or nit remain; **approve** if nothing is actionable.

## 6. Write the comments

**Load `references/voice.md` now** (in this skill directory) and follow it. It holds the register, the rewrite gallery, and the suggestion-block rules. The non-negotiable rules:

- A comment reads like a teammate typed it into the review box in 30 seconds, not like generated prose.
- `minor` / `question` / `nit`: **one line.** A direct question, a flat imperative, or "X should be enough" naming the alternative. Skip the justification when the ask is self-evident.
- `major` / `blocker`: at most 2 sentences of evidence plus 1 ask. If a sentence explains *why the consequence is bad* rather than *what it is*, delete it.
- **No em dashes.** Use a comma, colon, semicolon, or a second sentence.
- One ask per comment. Never merge two findings into one block.
- Vary how you open. Never the same sentence shape twice in a row.
- Include a GitHub `suggestion` fence when the fix is a concrete 1 to 3 line replacement of exactly the anchored line(s), and you are certain of the replacement. Not for design questions or multi-file changes.

**Shrink pass, mandatory.** The first draft of every comment is too long, because the justification is still fresh in your head. Rewrite each one against the limits above. Final test per comment: could a teammate have typed this without reading your investigation? If not, it is still carrying your reasoning. Cut until it does.

## 7. Validate the file before you finish

Mechanical, and cheap. Fix anything that fails before you report done:

- [ ] `bash ${CLAUDE_SKILL_DIR}/scripts/check-review.sh pr-reviews/<branch-key>.md <base>...<head>` prints `ok`. It checks that every `inline` anchor, and every line of a range, is a line the diff added, that headers are numbered from 1 in severity order, and that no em dash is left.
- [ ] Every cited symbol is actually on that line in `git show <head>:<path>`.
- [ ] Every `suggestion` block replaces exactly the line(s) its comment anchors to, at the same indentation.
- [ ] Removed-behavior and caller audits ran (step 4d).
- [ ] Every `blocker` and `major` has a verdict from the verifier, every `minor` was checked by the verifier or by you, and the verdict table was applied.
- [ ] No subagent ran outside step 4c, the verifier, or a critical security finding.
- [ ] Security pass run if the diff touched anything on its trigger list, and the trust-boundary path was opened if the change moved one.
- [ ] No placeholders, no `[fill in]`, no tool output, no diff dumps.
- [ ] Coverage line lists read-in-full vs skimmed vs not-opened, with the reason for anything skipped.
- [ ] One finding per block; no duplicates of each other or of an existing human comment.
- [ ] **Claims checked** lists every factual claim in the PR body, each true, false, or unverifiable, with evidence.
- [ ] **Ticket** lists every ticket requirement, each covered, missing, or contradicted, or says why no ticket was read.
- [ ] **Tests run** names each command and its result, or why it could not run.
- [ ] If a companion PR is named, **Companion PR** states what the contract check found.

**Re-review of a branch:** read the existing `pr-reviews/<branch-key>.md` before overwriting it, and add one line under the recommendation saying which earlier comments are now resolved and which are still open. Comments already posted to the PR are existing review comments (step 1); do not write them again.

If `pr-reviews/` is not gitignored (`git check-ignore -v pr-reviews/`), mention that once in the summary so the file does not get committed by accident.

## 8. Output format

**File, `pr-reviews/<branch-key>.md`:**

```markdown
# PR Review: <branch or PR title>

**What this PR does:** <one or two sentences.>

**Recommendation: <approve | approve with comments | request changes>.** <one line why.>

**Coverage:** read in full: <files>; skimmed: <files>; not opened: <files + why>.

**Tests run:** <command: result, for each test file; or why it could not run.>

**Verification:** <n> sent to the verifier: <n> confirmed, <n> plausible, <n> refuted and dropped. Gap sweep found <n>. Or: no verifier, because there was no blocker or major.

**Claims checked:** <claim: true | false | unverifiable, with file:line. One line each. "No factual claims" if the body has none.>

**Ticket:** <KEY: requirement: covered | missing | contradicted, with file:line. One line each. Or why no ticket was read.>

**Companion PR:** <what the contract check found. Omit this line only when no companion PR is named.>

---

## 1. [major] inline app/controllers/foo_controller.rb:66

> Paste-ready comment, anchored to that exact line.

## 2. [minor] inline app/serializers/bar_serializer.rb:20-21

> Paste-ready comment whose suggestion replaces lines 20 and 21.

## 3. [nit] general

> PR-wide comment (split the PR, convention, etc.).

---

**Checked and fine:** <what you verified and cleared. Optional, when worth noting.>
```

**Chat summary after writing the file:**

1. Two or three lines: what the PR does plus your recommendation.
2. The coverage line, including anything not opened, and the verification line. Surface skips here too, not only in the file.
3. CI state, the result of the PR's own tests, draft status, and any assumption or missing context worth stating.
4. The priority-ordered comment headers (`[severity] file:line`). Bodies stay in the file.
5. Any false claim in the PR body, and any ticket requirement that is missing or contradicted.
6. The path to the saved file.

## 9. Ask, then post

If the review is of a PR and has at least one comment, end by asking: "Post <n> comments to #<pr>?" Use the question tool when one exists. A yes approves this one post; a later run asks again.

On yes:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/post-review.sh pr-reviews/<branch-key>.md <pr> <base>...<head>
```

- The script re-runs `check-review.sh`, since the user may have edited the file.
- It stops if the PR's head commit is not `<head>`, because anchors from another commit land on the wrong lines.
- It posts one `COMMENT` review: `inline` blocks as line comments, `general` blocks as the review body, or the Recommendation line when there is no `general` block. Nothing else in the file is posted.
- It never approves or requests changes; that stays the user's call on GitHub.

Report the review URL it prints. If it fails, report its output and do not post by hand. On no, stop; the file stays.
