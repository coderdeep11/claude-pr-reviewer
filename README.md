# pr-reviewer

A Claude Code skill that reviews a pull request like a senior engineer and writes **paste-ready review comments**, each anchored to the exact `file:line` it belongs on.

## What it does

- Reads every substantial changed file, the PR description, existing review comments, CI state, and the linked Jira ticket (when the Atlassian MCP is connected).
- Runs the test files the PR adds or changes, and nothing else.
- Checks the PR body's claims and the ticket's requirements against the code.
- Audits removed guards and existing callers, not just added lines.
- Runs a security checklist when the diff touches auth, SQL, PII, uploads, and similar areas.
- Sends every `blocker` and `major` to a second agent that tries to disprove it before it reaches you.
- Writes short, human-sounding comments, with one-click GitHub `suggestion` blocks where the fix is mechanical.
- Validates every anchor against the diff, so no comment lands on the wrong line.
- Offers to post everything as one `COMMENT` review. It never approves or requests changes for you.

It is read-only: no commits, pushes, checkouts, or edits. The only file it writes is `pr-reviews/<branch>.md`.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- `git`, `bash`, `awk`, `jq`
- [`gh`](https://cli.github.com), authenticated, for PR context and posting
- Optional: the Atlassian MCP, for Jira ticket checks. Without it, the review scopes from the PR alone.

## Install

Pick one.

### Option 1: plugin (easiest to update)

In Claude Code:

```
/plugin marketplace add coderdeep11/claude-pr-reviewer
/plugin install pr-reviewer@claude-pr-reviewer
```

To turn it on for everyone working in a repo, commit this to that repo's `.claude/settings.json`:

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

### Option 2: copy into your codebase

Commit the skill into your repo so everyone who clones it gets it. From your repo root:

```bash
tmp=$(mktemp -d)
git clone --depth 1 https://github.com/coderdeep11/claude-pr-reviewer "$tmp"
mkdir -p .claude/skills
cp -R "$tmp/plugins/pr-reviewer/skills/pr-reviewer" .claude/skills/
rm -rf "$tmp"
echo "pr-reviews/" >> .gitignore
```

### Option 3: just for you, in every repo

Same as Option 2, but copy to `~/.claude/skills/` instead of `.claude/skills/`.

## Use

Ask Claude Code in plain words. The skill picks itself up:

```
review PR #482
review this branch against main
```

Or call it directly: `/pr-reviewer` if you copied it in, `/pr-reviewer:pr-reviewer` if you installed the plugin.

You get:

1. `pr-reviews/<branch>.md` with a recommendation, a coverage line, test results, checked claims, ticket coverage, and numbered comments in severity order.
2. A short summary in chat.
3. A prompt: "Post N comments to #PR?" Say yes to post them as one review.

Add `pr-reviews/` to your `.gitignore` so review files don't get committed.

## Make it yours

The skill follows your repo's own rules (`CLAUDE.md`, `CONTRIBUTING.md`, linter configs), not its own taste. To change the comment style, edit `references/voice.md`. To change the workflow, edit `SKILL.md`.

## Layout

```
plugins/pr-reviewer/skills/pr-reviewer/
  SKILL.md              workflow
  references/voice.md   comment style guide
  scripts/anchors.sh    line numbers straight from the diff
  scripts/check-review.sh  validates the review file
  scripts/post-review.sh   posts it as one GitHub review
```

## License

MIT
