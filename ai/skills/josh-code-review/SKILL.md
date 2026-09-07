---
name: josh-code-review
description: Review code against Josh's smell list before calling work done. Flags explanatory comments, over-long comments, premature abstraction, Ruby metaprogramming, meaningless variable names, bad migration timestamps, and data backfills hidden in migrations. Also runs the project linter on changed files and tightens prose in docs and PR text. Use when reviewing a diff, a PR, a branch, or a file, and as a self-check before committing or opening a PR.
---

# Code review

Review changed code against the rules below. Report findings only. Do not fix unless asked.

## Scope

Default target is the uncommitted diff plus commits on the current branch that are not on the main branch:

```bash
git diff --stat && git diff $(git merge-base HEAD main)...HEAD --stat
```

If the user names a PR, branch, or path, review that instead.

## Rules: all languages

**Comments that explain code.** A comment restating what the line below does is noise. Delete it. A comment is earned only when it records an unintuitive or hidden business decision that the code cannot express: a workaround for a third-party bug, a legal or billing rule, a deliberate deviation from the obvious approach.

```ruby
# bad: restates the code
# increment the retry counter
retries += 1

# good: records a decision the code cannot show
# Provider rejects a second charge within 3s, so retry after the window.
sleep 3
```

**Comments longer than 3 lines.** Cap is 3 lines. Past that, the reasoning belongs in the commit message, a PR description, or a doc. Flag any comment block over the cap and say where the text should live instead.

**Premature abstraction.** Flag a new base class, module, interface, config option, or generic helper introduced for a single call site, or for a second use case that is speculative rather than in the diff. Count the actual call sites. Two similar blocks is not duplication worth abstracting; three with a stable shape might be. Prefer the concrete version until the third case exists.

## Rules: Ruby

**Metaprogramming.** Flag `public_send`, `send`, `define_method`, `method_missing`, `const_get`, `instance_variable_get`, and dynamic method construction from strings. These defeat grep, static analysis, and editor jump-to-definition. Replace with an explicit case statement, a hash of lambdas, or plain method calls.

```ruby
# bad
record.public_send("#{field}_status")

# good
case field
when :payment then record.payment_status
when :refund  then record.refund_status
end
```

**Variable names.** Flag names that carry no meaning: `data`, `result`, `temp`, `obj`, `res`, `x`, `arr`, `h`, and block args like `|e|` or `|i|` where the element has a real name. Suggest the domain word: `payment`, `matched_customers`, `unpaid_invoice_ids`.

## Rules: Rails migrations

**Timestamps.** Every file in `db/migrate/` needs a real generated timestamp. A filename whose time portion is `000000` (for example `20260901000000_add_foo.rb`) was hand-written and will order unpredictably against generated migrations. Regenerate with `bin/rails generate migration` and move the body across.

```bash
ls db/migrate | grep -E '^[0-9]{8}0{6}_'
```

**Data changes.** Migrations change schema. Backfills, corrections, and any update to existing rows belong in a rake task under `lib/tasks/`, run deliberately after deploy. A backfill inside a migration blocks the deploy, cannot be retried in isolation, and reruns differently on a fresh database. Flag `update_all`, `find_each`, `each` over records, and model class references inside a migration.

## Hygiene pass

Run these as part of the review, on changed files only.

1. **Linter.** Detect what the project uses and run it against the changed files. Ruby: `bundle exec rubocop $(git diff --name-only --diff-filter=d $(git merge-base HEAD main) -- '*.rb')`. JS and TS: `eslint`, or the project's `lint` script from `package.json`. Skip silently if the project has no linter configured. Report failures with the file and rule; do not autocorrect without asking.
2. **Documentation.** If the change made a README, doc, or comment stale, say which file and what is now wrong.
3. **Prose.** Docs, README text, commit messages, and PR descriptions should be short and direct. Cut LLM tells: "delve", "leverage", "robust", "seamless", "it's worth noting", "in today's world", tricolon padding, a summary paragraph restating the previous paragraph. No em dashes; rewrite with a full stop, comma, or colon. State the change and why, then stop.

## Output

One line per finding, most severe first:

```
path/to/file.rb:42 explanatory comment. Restates the assignment below. Delete.
```

Group by rule if there are many. End with the linter result and a one-line verdict. If the diff is clean, say so in one line and stop; no praise section, no summary of what the code does.
