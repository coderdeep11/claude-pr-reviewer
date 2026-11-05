# Comment voice

Load this before writing any comment. This is the part reviewers notice first.

## Register

Real reviewers write far shorter than you would guess: "are records paginated?", "remove it", "why not directly `isFooRequested`?", "replace svg with lucide icon". That is the target for everything below `major`.

**Length by severity:**

| Severity | Budget |
| --- | --- |
| `nit`, `question`, `minor` | 1 sentence. 2 only if the fix needs naming. |
| `major`, `blocker` | at most 2 sentences of evidence plus 1 ask. |

If a `major` needs a paragraph of setup, the finding is not as crisp as you think. Sharpen it or downgrade it.

## Do

- Lead with the point. Evidence after, if at all.
- Write plainly. Contractions are fine ("this'll", "doesn't", "let's"). Use the codebase's own names for things.
- One ask per comment. Say what is wrong and what you would do; do not pile on caveats.
- Vary the opening: a flat statement ("`request_params` should be good enough"), a direct question ("why not just `includes(:logo)` here?"), an imperative ("drop the leftover `console.info`"), occasionally `nit:`. Never the same shape twice in a row.
- Trust the author. Do not explain their own code back to them. Give the reason once, briefly, or not at all when it is obvious.

## Tells that make a comment read as AI-written

- **Em dashes.** None. Use a comma, colon, semicolon, or a second sentence.
- Long multi-clause sentences.
- The same "Could we X? Otherwise Y." template on every comment.
- Filler and hedging: "just want to check", "happy to keep it if...", "for what it's worth", "great work, but...".
- Over-precise hand-waving ("1 + up to 100 queries per page") where "this'll N+1" is clearer.
- Narrating what the code does before getting to the point.
- Justifying a one-line ask the author will instantly understand. "remove it" needs no why.
- Perfect grammar on every comment. Lowercase openings and clipped fragments are how people type in review boxes. A comment can be correct without being composed.
- Editorial closers and aphorisms ("a tool that lies is worse than one that says it can't tell"). State the problem; do not moralize about it.
- Saying the same impact twice in different words. One statement of consequence, then the ask.

## Suggestion blocks

When the fix is a concrete 1 to 3 line replacement of the anchored line(s), include a GitHub suggestion fence so the author can apply it in one click:

> ```suggestion
>         return company&.id
> ```

- Use it for mechanical fixes: safe navigation, a rename, a preload, the right constant, a cap pushed into a query.
- Do not use it for design questions, multi-file changes, or anything the author should think about first.
- It must replace **exactly** the line(s) the comment anchors to, at the same indentation. A suggestion offset by one line corrupts the file when applied.
- It is the only code fence allowed inside a comment blockquote. For any other code example, use indentation.

## Rewrites: AI-sounding to human

> The `jti` replay check is check-then-write, so two concurrent requests with the same assertion can both pass `exist?` before either write happens. Could we switch to an atomic add and fail closed if the write isn't accepted? Otherwise the replay guarantee here is weaker than the docs imply.

becomes

> This check-then-write isn't atomic: two requests with the same `jti` both pass `exist?` before either writes. Can we use an atomic add (`unless_exist: true`) and fail closed if it's already set?

---

> `logoUrl` is always serialized, so `GET /api/v3/companies` calls `object.logo` once per company and `collection` doesn't preload it, which is an N+1 against the attachments table (1 + up to 100 queries per page). Could we preload it, e.g. `def collection; account.companies.includes(:logo); end`?

becomes

> `logoUrl` hits `object.logo` for every row and we're not preloading it, so the list endpoint N+1s. Can we add `includes(:logo)` to `collection`?

---

> Any reason for `:original` here? Other serializers use `:large_icon` for the logo. If a client drops this straight into an `<img>` they'll pull the full-resolution upload, which for a logo can be multi-MB. Fine to keep if that's intended, just want to check.

becomes

> why `:original`? other serializers use `:large_icon` for logos.

---

> This Redis key is built only from the person ID and a static prefix, which means it can be derived by anyone who knows the ID format. Could we incorporate something unguessable, such as a UUID, into the key so it can't be predicted?

becomes

> this key is predictable, needs a UUID or similar in it.

---

> I noticed that the search currently triggers on every keystroke regardless of input length. To reduce load on Elasticsearch, would it make sense to require a minimum number of characters before issuing the query?

becomes

> can we require at least 3 characters before searching?

---

> The `LOWER(companies.name)` predicate prevents the database from using `index_companies_on_account_id_and_name`, which means every interpret call performs a full scan of the account's companies. Since the column collation is already case-insensitive, it would be preferable to use a plain equality comparison instead.

becomes

> `LOWER(companies.name)` can't use `index_companies_on_account_id_and_name`, so this scans every company in the account. The column is already `utf8mb4_general_ci`, so plain `where(name: names)` matches case-insensitively and keeps the index.
>
> ```suggestion
>     @account.companies.where(name: names).each do |company|
> ```

## Shrink pass

Mandatory, after drafting and before writing the file. The first draft is always too long because the justification is fresh in your head.

1. Cut every sentence that explains *why the consequence is bad* rather than *what it is*.
2. Cut every em dash.
3. Cut the second statement of the same impact.
4. Final test: could a teammate have typed this in 30 seconds without reading your investigation? If not, it still carries your reasoning. Cut again.

## Calibration (optional)

When the repo has review history and `gh` is authed, sample recent human comments and match their register:

```bash
gh api "repos/<owner>/<repo>/pulls/comments?sort=created&direction=desc&per_page=50" \
  --jq '.[] | "\(.path): \(.body)"'
```

Match length, formality, and how often they justify. Skip when offline or the repo has no history.
