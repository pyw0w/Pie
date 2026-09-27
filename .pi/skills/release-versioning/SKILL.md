---
name: release-versioning
description: Decide the version bump and write the commit messages that produce it, predict or inspect a PiCode release, and check what CI will do with a push to main. Use when committing, releasing, tagging, writing changelog/release notes, or editing version metadata (MARKETING_VERSION, CURRENT_PROJECT_VERSION, CFBundleShortVersionString) in this repository.
---

# Release and versioning for PiCode

PiCode has **no version number in the source tree**. The version is derived
from commit messages by `Tools/Release/version.sh` and stamped into the app at
build time. Your commit subject is therefore the only input that decides what
the next release is called.

## 1. Write the commit

```text
<type>[scope][!]: <imperative summary, ≤72 chars, no full stop>

<why — only when the diff does not make it obvious>

BREAKING CHANGE: <what broke and how to migrate>   <- only when it broke
```

| Type | Bump |
| --- | --- |
| `fix:` `perf:` `refactor:` `revert:` `build:` | patch |
| `feat:` | minor |
| `docs:` `chore:` `ci:` `style:` `test:` | none (releases nothing alone) |
| anything else / no type | patch (still ships, but wrong) |
| `type!:` or a `BREAKING CHANGE:` footer | major |

Classification is per commit, over **every commit since the last `vX.Y.Z`
tag**; the highest bump wins. Scope examples that fit this repo: `sidebar`,
`composer`, `transcript`, `discovery`, `settings`, `palette`, `ci`, `docs`.

Good:

```text
feat(discovery): find pi in the agent bin directory
fix(transcript): stop a compaction row from splitting a fold
chore(ci): gate releases on the headless harnesses
```

Bad, and what happens to them:

```text
working                 -> no type -> patch, and the notes say "Other"
UI improvements         -> no type -> patch, and nobody learns what changed
feat: add x (wip)       -> subject is fine but says nothing useful; rewrite it
```

Breaking changes are declared twice: `!` on the subject **and** a
`BREAKING CHANGE:` footer. The footer alone is enough for the bump; use both so
the notes carry the migration text.

## 2. Predict what CI will do

```bash
./Tools/Release/version.sh bump        # major | minor | patch | none | initial
./Tools/Release/version.sh current     # last released version (0.0.0 if none)
./Tools/Release/version.sh next        # version of the next release
./Tools/Release/version.sh releasable  # yes | no
./Tools/Release/version.sh notes       # the notes CI will publish, verbatim
```

The first release is always `1.0.0`; after that the last tag is the base.

## 3. What the push to main does

`.github/workflows/release.yml`, in order, all of it read-only towards the
repository:

1. `Tools/CI/verify.sh` with `REQUIRE_PI=1` — type-check, JSON scanner, RPC
   against a freshly installed real `pi`, Pi path resolution. Failure = no
   release.
2. `version.sh` — bump and version from the commits since the last tag.
3. `Tools/Release/build-app.sh <version>` — arm64 `Pie.app`, `MARKETING_VERSION`
   and `CURRENT_PROJECT_VERSION` passed to `xcodebuild` (never edited in the
   project file), ad-hoc signed, zipped to `dist/Pie-<version>-arm64.zip`, and
   the stamped `CFBundleShortVersionString` is asserted against the computed
   version.
4. `gh release create v<version>` with `version.sh notes` and the zip, tagged at
   the pushed commit.

If every pending commit is `chore`/`docs`/`ci`/`style`/`test`, step 4 is
skipped: no tag, no release, no failure.

## 4. Never

- Never edit `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in
  `PiCode.xcodeproj/project.pbxproj` — they are placeholders CI overwrites at
  build time.
- Never `git tag` or `gh release create` manually. CI owns `vX.Y.Z`.
- Never write a `CHANGELOG.md` or hand-edit release notes — notes come from
  commit subjects.
- Never add a CI step that commits or pushes; that loops back into this
  repository.

## 5. If a version came out wrong

Do not rewrite history and do not delete a published tag: tags are the base for
the next computation. Ship a follow-up commit whose type says the truth
(`fix!: …` if a breaking change went out as a patch) and let the next push
carry it. If nothing has been published yet, rewriting the commits before the
push is fine — the tag does not exist yet.

## 6. Pre-commit gate

```bash
./Tools/CI/verify.sh                   # type-check + JSON/RPC/path harnesses
./Tools/SmokeTest/run-replay.sh        # transcript/folding changes
./Tools/SmokeTest/run-open.sh          # session-tree changes
./Tools/SmokeTest/run-sidebar-*.sh     # sidebar geometry/behaviour (GUI)
./Tools/SmokeTest/run-composer.sh      # composer keys and box shape (GUI)
```

CI runs only `Tools/CI/verify.sh`; the GUI harnesses are your local evidence.
