#!/bin/bash

# Resolves the `nimble-version` action input into a concrete install plan.
#
# Emits three key=value pairs on stdout, and to $GITHUB_OUTPUT when set:
#   kind     "release" (download a prebuilt asset) or "source" (build a commit)
#   version  the resolved release version, or the original input for a source build
#   sha      the full commit SHA for a source build, empty otherwise
#
# Resolution is first-match-wins, so every value that worked before still takes
# the same path; only unrecognised input falls through to the commit-ish branch.

set -eu

DATE_FORMAT="%Y-%m-%d %H:%M:%S"

NIMBLE_REPO="nim-lang/nimble"

# Logging goes to stderr so stdout carries only the key=value contract.
info() {
  echo "$(date +"$DATE_FORMAT") [INFO] $*" >&2
}

err() {
  echo "$(date +"$DATE_FORMAT") [ERR] $*" >&2
}

# Prints the response body on stdout; returns non-zero on any non-200 status.
# The Authorization header is omitted entirely when no token was supplied --
# sending an empty bearer token makes GitHub reject the request outright.
api_get() {
  local url response http_code
  url=$1
  if [[ -n "$repo_token" ]]; then
    response=$(curl -sSL -w $'\n%{http_code}' \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${repo_token}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url")
  else
    response=$(curl -sSL -w $'\n%{http_code}' \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url")
  fi

  http_code=${response##*$'\n'}
  if [[ "$http_code" != "200" ]]; then
    return 1
  fi
  printf '%s' "${response%$'\n'*}"
}

# All release-shaped tags, one per line, `v` prefix stripped.
# per_page=100 covers nimble's ~45 tags with no Link header; if it ever exceeds
# 100 tags this needs to follow pagination.
list_tags() {
  local body
  if ! body=$(api_get "https://api.github.com/repos/${NIMBLE_REPO}/git/refs/tags?per_page=100"); then
    return 1
  fi
  printf '%s' "$body" |
    jq -r 'if type == "array" then .[].ref else empty end' |
    sed -E 's:^refs/tags/v::' |
    sed -E 's:^refs/tags/::' |
    { grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || true; }
}

# A tag is not a download. nimble pushes a tag, builds its binaries into a draft
# release, and publishes that draft by hand -- 34 minutes later for 0.26.2, three
# and a half hours for 0.26.1 -- so until then the newest tag has nothing behind
# it. The two lookups below see only published releases, never drafts or
# prereleases (the rolling 'latest' is one).

# The version of GitHub's latest release, `v` prefix stripped.
latest_release() {
  local body
  if ! body=$(api_get "https://api.github.com/repos/${NIMBLE_REPO}/releases/latest"); then
    return 1
  fi
  printf '%s' "$body" |
    jq -r '.tag_name // empty' |
    sed -E 's:^v::' |
    { grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || true; }
}

# Every published release version, one per line, `v` prefix stripped.
# per_page=100 covers nimble's ~45 releases; like list_tags, this needs to follow
# pagination if that is ever exceeded.
list_releases() {
  local body
  if ! body=$(api_get "https://api.github.com/repos/${NIMBLE_REPO}/releases?per_page=100"); then
    return 1
  fi
  printf '%s' "$body" |
    jq -r 'if type == "array" then .[] | select((.draft or .prerelease) | not) | .tag_name else empty end' |
    sed -E 's:^v::' |
    { grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || true; }
}

latest_version() {
  sort -V | tail -n1
}

tag_regexp() {
  echo "$1" |
    sed -E \
      -e 's/\./\\./g' \
      -e 's/^/^/' \
      -e 's/x$//'
}

# Resolves a full SHA, short SHA, branch name or tag to a full commit SHA.
resolve_commitish() {
  local body ref
  ref=$1

  # The ref is interpolated into an API path, so keep it to git-legal characters.
  # Without this, a value like '../../../repos/other/repo/commits/main' would be
  # collapsed by curl into a request against a different repository.
  if [[ ! "$ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || [[ "$ref" = *".."* ]]; then
    err "'${ref}' is not a valid git ref"
    return 1
  fi

  if ! body=$(api_get "https://api.github.com/repos/${NIMBLE_REPO}/commits/${ref}"); then
    return 1
  fi
  printf '%s' "$body" | jq -r '.sha'
}

emit() {
  printf '%s=%s\n' "$1" "$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  fi
}

# parse commandline args
nimble_version="latest"
repo_token=""

while ((0 < $#)); do
  opt=$1
  shift
  case $opt in
  --nimble-version)
    nimble_version=$1
    shift
    ;;
  --repo-token)
    repo_token=$1
    shift
    ;;
  *)
    err "Unknown option '${opt}'"
    exit 1
    ;;
  esac
done

nimble_version=$(echo "$nimble_version" | tr -d '[:space:]')

if [[ -z "$nimble_version" ]]; then
  err "nimble-version is empty"
  exit 1
fi

# A `v`-prefixed release tag names exactly the code in the matching release, so
# route it to the prebuilt download rather than a multi-minute source build.
# Wildcards are accepted with the prefix too, for symmetry with the bare forms.
if [[ "$nimble_version" =~ ^v([0-9]+\.[0-9]+(\.[0-9]+)?|[0-9]+\.[0-9]+\.x|[0-9]+\.x)$ ]]; then
  nimble_version=${nimble_version#v}
fi

kind=""
version=""
sha=""

if [[ "$nimble_version" = "nightly" ]]; then
  # The rolling 'latest' prerelease is rebuilt on every push to nimble's master.
  info "Using the nightly build from the rolling 'latest' tag"
  kind="release"
  version="latest"

elif [[ "$nimble_version" = "latest" ]]; then
  info "Finding the latest released version..."
  if ! version=$(latest_release); then
    err "Failed to fetch the latest nimble release from GitHub. If this is a rate"
    err "limit, set the repo-token input, or pin an exact version, which needs no"
    err "API call."
    exit 1
  fi
  if [[ -z "$version" ]]; then
    err "Failed to determine the latest version"
    exit 1
  fi
  info "Latest stable version is: $version"
  kind="release"

elif [[ "$nimble_version" =~ ^[0-9]+\.[0-9]+\.x$ ]] || [[ "$nimble_version" =~ ^[0-9]+\.x$ ]]; then
  if ! releases=$(list_releases); then
    err "Failed to fetch nimble releases from GitHub. If this is a rate limit, set"
    err "the repo-token input, or pin an exact version, which needs no API call."
    exit 1
  fi
  version=$(printf '%s' "$releases" | { grep -E "$(tag_regexp "$nimble_version")" || true; } | latest_version)
  if [[ -z "$version" ]]; then
    err "No published nimble release matches '${nimble_version}'"
    exit 1
  fi
  info "Resolved ${nimble_version} to ${version}"
  kind="release"

elif [[ "$nimble_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  # Validating a typo early beats a confusing download error, but this path used
  # to need no API call at all. The unauthenticated API allows 60 requests an
  # hour per egress IP, shared across all GitHub-hosted runners, so a 403 here is
  # routine -- and an exact version needs nothing from the API to proceed.
  # Treat the lookup as advisory: only a successful fetch that lacks the tag is
  # grounds for failing.
  if tags=$(list_tags); then
    if ! printf '%s' "$tags" | grep -qx "$nimble_version"; then
      err "There is no nimble release '${nimble_version}'."
      err "Use 'latest' for the newest release, or 'nightly' to track master."
      exit 1
    fi
  else
    info "Could not reach the GitHub tags API; continuing without validating" \
      "'${nimble_version}'. If this is a rate limit, set the repo-token input."
  fi
  version="$nimble_version"
  kind="release"

else
  # Anything unrecognised is treated as a commit-ish and built from source.
  info "Resolving '${nimble_version}' as a commit-ish..."
  if ! sha=$(resolve_commitish "$nimble_version"); then
    err "'${nimble_version}' is not a valid nimble version or commit-ish."
    err "Accepted values: 'latest', 'nightly', a release version such as '0.16.4',"
    err "a wildcard such as '0.16.x', or a commit SHA, branch name or tag in"
    err "https://github.com/${NIMBLE_REPO}"
    exit 1
  fi
  if [[ -z "$sha" || "$sha" = "null" ]]; then
    err "Failed to resolve '${nimble_version}' to a commit SHA"
    exit 1
  fi
  info "Resolved '${nimble_version}' to commit ${sha}"
  version="$nimble_version"
  kind="source"
fi

emit kind "$kind"
emit version "$version"
emit sha "$sha"
