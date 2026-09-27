# AGENTS.md — rules for working on PiCode (Pie)

Authoritative docs for the codebase itself live elsewhere — read them before
you change anything:

| Question | Read |
| --- | --- |
| Build, run, verify, architecture, invariants | `PROCESS.md` (§1 rules, §3 commands) |
| What the app is and how it is meant to behave | `README.md` |
| What is scheduled and what is done | `TODO.md`, `IMPLEMENTATION.md` |

This file is only about **how work is committed and how a version comes out of
it**. The detailed procedure is the `release-versioning` skill
(`.pi/skills/release-versioning/SKILL.md`) — load it when you are about to
commit, release, or touch version metadata.

## Commits decide the version

There is no version number anywhere in the source tree. On every push to
`main`, `.github/workflows/release.yml` computes the next version from the
**Conventional Commit subjects** of every commit since the last `vX.Y.Z` tag
(`Tools/Release/version.sh`), then builds, tags, and publishes a GitHub Release.
If a commit message says nothing about what changed, the version is a guess.

So every commit you make must look like:

```text
<type>[optional scope][!]: <imperative summary>

<why, when it is not obvious from the diff>
```

| Type | Bump | Use for |
| --- | --- | --- |
| `fix:` | patch | a bug is corrected |
| `feat:` | minor | new user-visible capability |
| `perf:` `refactor:` `revert:` `build:` | patch | behaviour-preserving or build changes |
| `docs:` `chore:` `ci:` `style:` `test:` | none | releases nothing on its own |
| any other type, or no type at all | patch | still ships — but it should have been one of the above |
| `type!:` or a `BREAKING CHANGE:` footer | major | anything that changes existing behaviour/files |

Examples that are correct for this repo:

```text
feat(discovery): find pi in the agent bin directory
fix: keep the sidebar pitch when a project folds
chore(ci): gate releases on the headless harnesses
feat!: drop the legacy session index      <- major, needs a footer saying why
```

Rules:

- **Imperative mood, ≤ 72 characters, no trailing period, no `WIP`/`stuff`.**
  `fix: stop long sessions from stalling the UI`, not `fix: fixed bug`.
- **Scope when the change is local**: `sidebar`, `composer`, `transcript`,
  `discovery`, `settings`, `palette`, `ci`, `docs`.
- **Breaking changes are always declared twice**: `!` on the subject and a
  `BREAKING CHANGE: <what and how to migrate>` footer in the body.
- **One logical change per commit.** A commit that mixes a feature with an
  unrelated refactor hides both from the release notes.
- The body explains *why*, not *what* — the diff already says what.

## Never do these

0. **Never set `user.name` / `user.email` in this repository.** Commits are
   authored from the global git config — `PyW0W <pyw0w@users.noreply.github.com>`
   — so they are attributed to the GitHub account that owns the repo. A
   repo-local identity silently overrides it and mis-attributes every commit
   from then on; `git config user.name` must show `PyW0W` before you commit.

1. **Do not edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`** in
   `PiCode.xcodeproj/project.pbxproj`. They are placeholders; the release build
   stamps the real values at build time (`Tools/Release/build-app.sh`).
2. **Do not create tags by hand**, and do not run `gh release create`. CI owns
   `vX.Y.Z`. A manual tag desynchronises the next computation.
3. **Do not write changelogs.** Release notes are generated from the commit
   subjects (`version.sh notes`); a hand-written `CHANGELOG.md` would drift.
4. **Do not make CI commit or push.** Any step that runs `git commit` or
   `git push` in this repo risks a loop and will fight the agent working tree.

## Predict the release before you push

```bash
./Tools/Release/version.sh bump        # major | minor | patch | none | initial
./Tools/Release/version.sh next        # the version the next release gets
./Tools/Release/version.sh notes       # the release notes CI will publish
```

Commits on a branch that never reaches `main` release nothing.

## Before you commit

Run what proves the change, not everything, but never nothing:

```bash
./Tools/CI/verify.sh                   # type-check + JSON/RPC/path harnesses
./Tools/SmokeTest/run-replay.sh        # transcript/folding changes
./Tools/SmokeTest/run-open.sh          # session-tree changes
```

GUI harnesses (`run-sidebar-*.sh`, `run-composer.sh`) need a window server.
CI runs only `Tools/CI/verify.sh`, so a green local GUI harness is the only
evidence you get for those.

## What happens on push to main

1. `Tools/CI/verify.sh` — type-check, JSON scanner, RPC against a real `pi`,
   Pi path resolution. A failure blocks the release.
2. `version.sh` — the version, from the commit subjects since the last tag.
3. `Tools/Release/build-app.sh` — arm64 `Pie.app`, version stamped, ad-hoc
   signed, zipped to `dist/Pie-<version>-arm64.zip`.
4. If the pending commits released nothing (only `chore`/`docs`/…), it stops:
   no tag, no release.
5. Otherwise `gh release create v<version>` with generated notes and the zip.

Anything pushed to another branch only verifies (via whatever workflow you run
locally); it never tags.
