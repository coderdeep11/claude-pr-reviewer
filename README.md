# pr-reviewer

**A Claude Code skill that reviews pull requests like a senior engineer, and writes comments like one.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757.svg)](https://claude.com/claude-code)

Ask Claude to review a PR. You get a short list of high-confidence comments, each pinned to the exact line it belongs on, written the way a teammate would type them. When you're happy with them, one "yes" posts them all to GitHub as a single review.

```
/plugin marketplace add coderdeep11/claude-pr-reviewer
/plugin install pr-reviewer@claude-pr-reviewer
```

Then: `review PR #482`

---

## Why use it

Most AI review output has the same problems: comments on the wrong line, confident claims that turn out false, and long, polite paragraphs nobody reads. This skill is built around fixing those.

| Problem | What pr-reviewer does |
| --- | --- |
| Comments land on the wrong line | Line numbers come straight from the diff, never from counting. A script rejects any anchor that isn't a line the PR added. |
| Confident but wrong findings | Every `blocker` and `major` goes to a second agent whose only job is to disprove it. Refuted findings are dropped. |
| Walls of generated prose | A built-in style guide and a mandatory "shrink pass" cut each comment to what a teammate would type in 30 seconds. |
| Pretends it read everything | A coverage line lists what was read in full, skimmed, and not opened, with the reason. |
| Reviews code the PR didn't touch | Comments must anchor to the change. Pre-existing issues are noted as "checked and fine", not raised. |
| Too eager to change things | Strictly read-only. It never commits, pushes, checks out, or edits your code. |

### The difference in one comment

Typical AI review comment:

> The `jti` replay check is check-then-write, so two concurrent requests with the same assertion can both pass `exist?` before either write happens. Could we switch to an atomic add and fail closed if the write isn't accepted? Otherwise the replay guarantee here is weaker than the docs imply.

pr-reviewer:

> This check-then-write isn't atomic: two requests with the same `jti` both pass `exist?` before either writes. Can we use an atomic add (`unless_exist: true`) and fail closed if it's already set?

And for small things, it's as short as a person would be:

> why `:original`? other serializers use `:large_icon` for logos.

---

## Install

Pick the option that fits how your team works.

### Option 1: Plugin (recommended)

Easiest to keep up to date. In Claude Code:

```
/plugin marketplace add coderdeep11/claude-pr-reviewer
/plugin install pr-reviewer@claude-pr-reviewer
```

**Turn it on for a whole repo.** Commit this to the repo's `.claude/settings.json` to register the marketplace and enable the plugin for everyone working in that repo:

```json
{
  "extraKnownMarketplaces": {
    "claude-pr-reviewer": {
      "source": { "source": "github", "repo": "coderdeep11/claude-pr-reviewer" }
    }
  },
  "enabledPlugins": {
    "pr-reviewer@claude-pr-reviewer": true
  }
}
```

### Option 2: Copy into your codebase

Vendor the skill into your repo so it's versioned with your code and everyone who clones gets it. From the repo root:

```bash
tmp=$(mktemp -d)
git clone --depth 1 https://github.com/coderdeep11/claude-pr-reviewer "$tmp"
mkdir -p .claude/skills
cp -R "$tmp/plugins/pr-reviewer/skills/pr-reviewer" .claude/skills/
rm -rf "$tmp"
echo "pr-reviews/" >> .gitignore
```

Commit `.claude/skills/pr-reviewer/` and the `.gitignore` change.

### Option 3: Just for you, in every repo

Same as Option 2, but copy to `~/.claude/skills/` instead of `.claude/skills/`, and skip the commit.

### Requirements

| Tool | Needed for |
| --- | --- |
| [Claude Code](https://claude.com/claude-code) | running the skill |
| `git`, `bash`, `awk` | reading the diff and validating anchors |
| [`gh`](https://cli.github.com), logged in | PR context, CI status, existing comments, posting |
| `jq` | posting the review |
| Atlassian MCP (optional) | checking the PR against its Jira ticket |

Without `gh`, you can still review a local branch or commit range. Without the Atlassian MCP, the review scopes from the PR alone and says so.

---

## Usage

Ask in plain words. Claude picks the skill up on its own:

```
review PR #482
review https://github.com/acme/api/pull/482
review this branch against main
review main...feature/invoice-export
```

Or call it directly: `/pr-reviewer:pr-reviewer` with the plugin, `/pr-reviewer` if you copied it in.

### What happens

1. Claude reviews the change and writes `pr-reviews/<branch>.md`.
2. You get a short summary in chat: recommendation, coverage, CI and test results, and the list of comment headers.
3. Claude asks: **"Post 3 comments to #482?"**
   - **Yes:** posts one GitHub review. Inline comments go on their lines; PR-wide comments go in the review body.
   - **No:** nothing is posted. Edit the file, paste comments by hand, or ask for a re-review.

It posts as a plain comment review. It never approves or requests changes; that stays your call.

### Example output

<details>
<summary><code>pr-reviews/invoice-export.md</code></summary>

````markdown
# PR Review: Add CSV export to invoices

**What this PR does:** Adds a CSV export endpoint for invoices and an Export button on the invoices page.

**Recommendation: request changes.** The export isn't scoped to the current account, so any signed-in user can download another account's invoices.

**Coverage:** read in full: app/controllers/invoices_controller.rb, app/services/invoice_csv.rb, spec/requests/invoices_spec.rb; skimmed: app/views/invoices/index.html.erb; not opened: none.

**Tests run:** bundle exec rspec spec/requests/invoices_spec.rb: 6 examples, 0 failures.

**Verification:** 2 sent to the verifier: 2 confirmed, 0 plausible, 0 refuted and dropped. Gap sweep found 0.

**Claims checked:** "export only includes the current account's invoices": false, app/controllers/invoices_controller.rb:42 queries `Invoice.where(id: params[:ids])`.

**Ticket:** BILL-214: export filtered invoices as CSV: covered, app/services/invoice_csv.rb:8.

---

## 1. [blocker] inline app/controllers/invoices_controller.rb:42

> this isn't scoped to the account, so any invoice id works. Use `current_account.invoices`.
>
> ```suggestion
>     invoices = current_account.invoices.where(id: params[:ids])
> ```

## 2. [major] inline app/services/invoice_csv.rb:15

> `invoice.customer.name` runs per row and nothing preloads `customer`, so big exports N+1. Can we `includes(:customer)` in the controller?

## 3. [nit] inline app/services/invoice_csv.rb:3

> drop the leftover `puts`.
````

</details>

`suggestion` blocks become GitHub's one-click "Commit suggestion" button.

---

## How it works

```mermaid
flowchart TD
    A["Resolve base and head"] --> B["Gather context: PR body, Jira ticket, CI, existing comments"]
    B --> C["Scope and size check"]
    C --> D["Read every changed file; run the PR's own tests"]
    D --> E["Audit removed guards and existing callers"]
    E --> F["Find candidates; security pass if relevant"]
    F --> G{"Any blocker or major?"}
    G -- yes --> H["Second agent tries to disprove each one"]
    G -- no --> I["Re-check minors at their cited lines"]
    H --> J["Write comments, then shrink them"]
    I --> J
    J --> K["Validate every anchor against the diff"]
    K --> L["Ask, then post one GitHub review"]
```

A few rules shape every review:

- **Read before claiming.** No function, field, or line is cited unless it was read in this session.
- **Certain, or it's a question.** If the evidence doesn't fully support a bug, it becomes a `question` or is dropped.
- **Coverage before signal.** Every substantial file is opened before the PR is judged. Large PRs are read in risk order (auth, migrations, money, shared services, public API) and the coverage line says what was skipped.
- **The repo decides taste.** Conventions come from your `CLAUDE.md`, `CONTRIBUTING.md`, linter configs, and PR template, not from the model's preferences.
- **Checks what the PR claims.** Every factual claim in the PR body, and every requirement in the linked ticket, is marked true, false, or unverifiable with a `file:line`.
- **Looks past the added lines.** It checks what the diff removed (guards, validations, tenant filters, transactions) and greps for callers the change could break.
- **Out-of-scope files get one comment.** Unrelated changes are rolled into a single "please split this PR" note instead of a line-by-line review.

### Severity

| Severity | Meaning |
| --- | --- |
| `blocker` | Likely data loss, security or auth breach, build break, migration failure, or outage |
| `major` | Likely correctness, integrity, privacy, or scalability bug to fix before merge |
| `minor` | Real issue with limited impact, or an edge case |
| `question` | Missing context that could hide a real issue, or an unconfirmed product decision |
| `nit` | Small, meaningful improvement; never cosmetic taste |

**Recommendation:** `request changes` if there's a blocker or a major worth fixing first, `approve with comments` if only minor, question, or nit remain, `approve` if nothing is actionable.

A critical security finding (SQL injection, auth bypass, an exposed credential) is verified first, then flagged in chat immediately, not left waiting in the file. A live credential is reported before the rest of the review finishes, because it needs rotating, not just removing from the branch.

### What it will and won't do

| Will | Won't |
| --- | --- |
| Read code, diffs, PR metadata, and the Jira ticket | Commit, push, fetch, check out, reset, or stash |
| Run the test files the PR adds or changes | Run the full suite or linters unless you ask |
| Write one file: `pr-reviews/<branch>.md` | Write or edit code or tests |
| Post one comment review after you say yes | Approve or request changes on your behalf |

---

## Customize

| To change | Edit |
| --- | --- |
| Comment tone and length | `references/voice.md` |
| The review workflow, severity rules, checklists | `SKILL.md` |

The skill already follows your repo's written rules, so often the better fix is adding a line to your `CLAUDE.md` or `CONTRIBUTING.md`.

---

## Troubleshooting

**`PR #482 head is <sha> but the review read <sha>; push or re-review first`**
New commits landed after the review, so the line numbers may have moved. Ask for a re-review. It reads the previous file and notes which comments are now resolved.

**`not a line this diff added: path:line`**
A comment is anchored on an unchanged or deleted line. GitHub can't place it there. Move it to the nearest added line, or change it to `general`.

**`no general comment or Recommendation line to use as the review body`**
The `**Recommendation:**` line was removed from the review file. Put it back, or add a `general` comment.

**The ticket wasn't checked**
The Jira key is read from the branch name, then the PR title, then commit messages (pattern `ABC-123`). Check that one of them has it and that the Atlassian MCP is connected.

**It asked for a base branch instead of guessing**
It won't `git fetch` on its own. Fetch the base yourself, or name it: `review this branch against origin/develop`.

**Review files show up in `git status`**
Add `pr-reviews/` to `.gitignore`.

---

## Repo layout

```
.claude-plugin/marketplace.json        marketplace entry
plugins/pr-reviewer/
  .claude-plugin/plugin.json           plugin manifest
  skills/pr-reviewer/
    SKILL.md                           the review workflow
    references/voice.md                comment style guide
    scripts/anchors.sh                 prints added or removed lines as path:LINE:content
    scripts/check-review.sh            validates anchors, numbering, severity order
    scripts/post-review.sh             posts the file as one GitHub review
```

## Contributing

Issues and pull requests are welcome. Before opening a PR:

```bash
claude plugin validate .
bash -n plugins/pr-reviewer/skills/pr-reviewer/scripts/*.sh
```

## License

[MIT](LICENSE)
