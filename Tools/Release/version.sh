#!/bin/bash
#
# The one place that decides what the next version of PiCode is.
#
#   version.sh current      last released version (`v1.2.3` -> `1.2.3`), or 0.0.0
#   version.sh bump         major | minor | patch | initial | none
#   version.sh next         the version the next release will be
#   version.sh releasable   `yes` if a release should happen, else `no`
#   version.sh notes        markdown notes for the pending commits
#   version.sh help         this text
#
# Every commit since the last `vX.Y.Z` tag is read as a Conventional Commit:
#
#   <type>[optional scope][!]: <imperative summary>
#
#   BREAKING CHANGE: footer, or `type!:`   -> major
#   feat:                                  -> minor
#   fix: perf: refactor: revert: build:    -> patch
#   any other type with a colon            -> patch
#   docs: chore: ci: style: test:          -> skipped (they release nothing alone)
#   no colon at all                        -> patch (ship it, but fix the message)
#
# The highest bump among the pending commits wins. Only commits -> no release.
# The first release is always `1.0.0`: the app has always been 1.0, and history
# before the first tag is not versioned twice.
#
# Runs on macOS's bash 3.2 — no `mapfile`, no `${x,,}`, no associative arrays.
# Only reads git; never writes, never tags. The tag is created by CI.
set -euo pipefail

cd "$(dirname "$0")/../.."

TAG_PATTERN='v[0-9]*.[0-9]*.[0-9]*'
FIRST_RELEASE='1.0.0'

# Conventional Commit subject shapes. Kept in variables: `!` and grouping are
# parsed more reliably that way than inline in `[[ =~ ]]`.
RE_BANG='^([A-Za-z]+)(\([^)]*\))?!:'
RE_COLON='^([A-Za-z]+)(\([^)]*\))?:'
RE_FEAT='^[Ff]eat(\([^)]*\))?:'
RE_BREAKING_FOOTER='^BREAKING[- ]CHANGE:'

die() { echo "version.sh: $*" >&2; exit 1; }

last_tag() {
    # Empty when there is no release yet.
    git describe --tags --match "$TAG_PATTERN" --abbrev=0 2>/dev/null || true
}

pending_commits() {
    local tag
    tag=$(last_tag)
    if [ -n "$tag" ]; then
        git log --format=%H "$tag..HEAD"
    else
        git log --format=%H HEAD 2>/dev/null || true
    fi
}

# Prints major | minor | patch | skip for one commit.
classify() {
    local sha="$1" subject body type
    subject=$(git show -s --format=%s "$sha")
    body=$(git show -s --format=%b "$sha")

    # A breaking change beats everything, wherever it is declared.
    if printf '%s\n' "$body" | grep -qE '^BREAKING[- ]CHANGE:'; then
        echo major
        return
    fi

    if [[ "$subject" =~ $RE_BANG ]]; then
        echo major
        return
    fi
    if [[ "$subject" =~ $RE_COLON ]]; then
        type=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
        case "$type" in
            feat) echo minor ;;
            fix|perf|refactor|revert|build) echo patch ;;
            docs|chore|ci|style|test) echo skip ;;
            *) echo patch ;;
        esac
        return
    fi
    # Not a Conventional Commit: still ships (a silent non-release is worse),
    # but the message should have followed the rules — see AGENTS.md.
    echo patch
}

bump() {
    local sha rank=none any=0
    while read -r sha; do
        [ -n "$sha" ] || continue
        any=1
        case "$(classify "$sha")" in
            major) echo major; return ;;
            minor) rank="minor" ;;
            patch)
                if [ "$rank" = "none" ]; then rank="patch"; fi
                ;;
            skip) : ;;
        esac
    done <<EOF
$(pending_commits)
EOF
    if [ "$any" -eq 0 ]; then
        echo none
    else
        echo "$rank"
    fi
}

current() {
    local tag
    tag=$(last_tag)
    if [ -z "$tag" ]; then
        echo "0.0.0"
    else
        echo "${tag#v}"
    fi
}

next() {
    local tag cur b major minor patch
    tag=$(last_tag)
    if [ -z "$tag" ]; then
        echo "$FIRST_RELEASE"
        return
    fi
    cur=${tag#v}
    b=$(bump)
    case "$b" in
        none|initial) echo "$cur" ;;
        major|minor|patch) : ;;
        *) die "unknown bump '$b'" ;;
    esac
    IFS=. read -r major minor patch <<EOF
$cur
EOF
    case "$b" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "$major.$((minor + 1)).0" ;;
        patch)
            # A missing/odd patch component (v1.2) still advances safely.
            case "$patch" in ''|*[!0-9]*) patch=0 ;; esac
            echo "$major.$minor.$((patch + 1))"
            ;;
    esac
}

releasable() {
    case "$(bump)" in
        none) echo no ;;
        *) echo yes ;;
    esac
}

notes() {
    local tag sha subject body type line
    tag=$(last_tag)
    printf '## %s\n\n' "$(next)"

    local breaking='' features='' fixes='' other=''
    # Walk the pending commits oldest first.
    local shas
    shas=$(pending_commits | sed '1!G;h;$!d')
    while read -r sha; do
        [ -n "$sha" ] || continue
        subject=$(git show -s --format=%s "$sha")
        body=$(git show -s --format=%b "$sha")
        line=$(printf '%s' "$subject" | sed 's/`//g')
        if printf '%s\n' "$body" | grep -qE "$RE_BREAKING_FOOTER"; then
            breaking="$breaking
- \`$line\`"
        elif [[ "$subject" =~ $RE_BANG ]]; then
            breaking="$breaking
- \`$line\`"
        elif [[ "$subject" =~ $RE_FEAT ]]; then
            features="$features
- \`$line\`"
        elif [[ "$subject" =~ $RE_COLON ]]; then
            type=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
            case "$type" in
                docs|chore|ci|style|test) other="$other
- \`$line\`" ;;
                *) fixes="$fixes
- \`$line\`" ;;
            esac
        else
            other="$other
- \`$line\`"
        fi
    done <<EOF
$shas
EOF

    if [ -n "$breaking" ]; then printf '### Breaking changes\n%s\n\n' "$breaking"; fi
    if [ -n "$features" ]; then printf '### Features\n%s\n\n' "$features"; fi
    if [ -n "$fixes" ]; then printf '### Fixes and other changes\n%s\n\n' "$fixes"; fi
    if [ -n "$other" ]; then printf '### Other\n%s\n\n' "$other"; fi
}

case "${1:-help}" in
    current) current ;;
    bump) bump ;;
    next) next ;;
    releasable) releasable ;;
    notes) notes ;;
    help|-h|--help)
        sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *) die "unknown command '$1' (current|bump|next|releasable|notes|help)" ;;
esac
