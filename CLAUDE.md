# SimpleYNAB

## Licensing: never merge a contribution without a CLA

This repo is AGPL-3.0-or-later and is intended for the App Store. Those two
facts conflict — the AGPL forbids imposing further restrictions on recipients,
and Apple's Usage Rules do exactly that. The only reason it can ship at all is
that **brzzdev is the sole copyright holder**, and a licensor isn't bound by the
licence they grant.

That exception dies the moment code lands that brzzdev doesn't own. Apple pulled
GNU Go in 2010 and VLC in 2011 over this; VLC's problem was that it had many
contributors and so *couldn't* grant the exception.

So:

- **Never merge an outside pull request**, however small, without a signed CLA or
  copyright assignment. This is irreversible once shipped.
- Treat PRs as out of scope entirely. `docs/agents/issue-tracker.md` sets
  "PRs as a request surface" to `no` deliberately — issues are the only intake.
- Source files carry `SPDX-License-Identifier: AGPL-3.0-or-later`, stamped by
  SwiftFormat and verified by `just format-check`. Don't strip it.

## Agent skills

### Issue tracker

Issues live as GitHub issues on `brzzdev/SimpleYNAB`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
