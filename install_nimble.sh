#!/bin/bash

# Installs nimble from an already-resolved install plan.
#
# Version resolution lives in resolve_nimble_version.sh, which runs as its own
# action step so that its resolved SHA is available to the cache key before this
# script runs.
#
#   --kind release  download the prebuilt asset for --nimble-version
#   --kind source   build the commit named by --sha from source

set -eu

DATE_FORMAT="%Y-%m-%d %H:%M:%S"

NIMBLE_REPO_URL="https://github.com/nim-lang/nimble"

info() {
  echo "$(date +"$DATE_FORMAT") [INFO] $*"
}

err() {
  echo "$(date +"$DATE_FORMAT") [ERR] $*" >&2
}

# A fallback to a non-native binary is exactly the kind of thing that otherwise
# passes unnoticed -- the job stays green and only `file` on the artifact shows
# anything is wrong -- so raise it as an annotation, not just a log line.
warn() {
  echo "$(date +"$DATE_FORMAT") [WARN] $*"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning title=Nimble architecture fallback::$*"
  fi
}

# Echoes a usable nim executable, preferring one the user already provided.
find_nim() {
  if command -v nim > /dev/null 2>&1; then
    command -v nim
    return 0
  fi
  if [[ -n "$nim_bootstrap_dir" ]]; then
    if [[ -x "${nim_bootstrap_dir}/bin/nim" ]]; then
      echo "${nim_bootstrap_dir}/bin/nim"
      return 0
    fi
    if [[ -x "${nim_bootstrap_dir}/bin/nim.exe" ]]; then
      echo "${nim_bootstrap_dir}/bin/nim.exe"
      return 0
    fi
  fi
  return 1
}

# Nim shells out to a C compiler. The Windows runners ship gcc, but MSYS2 is
# installed without being on PATH, so fall back to it before giving up.
ensure_c_compiler() {
  if command -v gcc > /dev/null 2>&1; then
    return 0
  fi
  local candidate
  for candidate in /c/msys64/mingw64/bin /c/mingw64/bin; do
    if [[ -x "${candidate}/gcc.exe" ]]; then
      info "Adding ${candidate} to PATH for the C compiler"
      PATH="${candidate}:${PATH}"
      export PATH
      return 0
    fi
  done
  err "No C compiler found; nim needs gcc to build nimble"
  return 1
}

# Windows release archives ship without CA certificates, so nimble cannot make
# HTTPS requests until one is provided. Source builds need the same treatment.
install_windows_certs() {
  info "Downloading SSL certificates..."
  curl -sSL "https://curl.se/ca/cacert.pem" -o "${nimble_install_dir}/bin/cacert.pem"
}

# Maps a runner architecture to the token nimble uses in its release asset
# names. Accepts both RUNNER_ARCH spellings (X64, ARM64) and `uname -m` ones.
#
# NOTE: these tokens are nimble's, not Nim's. nimble releases say `aarch64`
# where nim-lang/nightlies says `arm64`, so this must NOT be merged with
# target_name() in install_nim_bootstrap.sh -- they name different things.
asset_arch() {
  case "$1" in
  X64 | x86_64 | amd64) echo "x64" ;;
  ARM64 | arm64 | aarch64) echo "aarch64" ;;
  X86 | i686 | i386) echo "x32" ;;
  ARM | armv7l) echo "armv7l" ;;
  *) echo "" ;;
  esac
}

asset_url_for() {
  local a base
  a=$1
  base="${NIMBLE_REPO_URL}/releases/download"
  if [[ "$os" = "Windows" ]]; then
    echo "${base}/${release_tag}/nimble-windows_${a}.zip"
  elif [[ "$os" = "macOS" || "$os" = "Darwin" ]]; then
    echo "${base}/${release_tag}/nimble-macosx_${a}.tar.gz"
  else
    echo "${base}/${release_tag}/nimble-linux_${a}.tar.gz"
  fi
}

# Downloads and unpacks a prebuilt release asset.
#
# The download is a separate, checked step rather than `curl | tar`: in a
# pipeline only the LAST command's status is visible without pipefail, so a
# failed download would be silently unpacked as an empty archive, leaving an
# empty bin/ and a zero exit status.
#
# Native assets are not published for every arch on every release --
# macosx_aarch64 starts at 0.22.2, and Windows has no arm64 asset at all -- so
# a missing native asset falls back to x64 rather than failing. On Apple
# Silicon that binary runs under Rosetta, which is worth knowing about: a
# translated nimble sees `uname -m` as x86_64 and will go on to install an
# x86_64 Nim, whose NimScript VM then reports amd64 on an arm64 machine.
download_release() {
  local want_arch download_url archive

  # 'latest' is the rolling prerelease tag; everything else is a v-prefixed tag.
  if [[ "$nimble_version" = "latest" ]]; then
    release_tag="latest"
  else
    release_tag="v${nimble_version}"
  fi

  want_arch=$(asset_arch "$nimble_arch")
  if [[ -z "$want_arch" ]]; then
    warn "Unrecognised architecture '${nimble_arch}'; falling back to x64."
    want_arch="x64"
  fi

  if [[ "$os" = "Windows" ]]; then
    archive="nimble.zip"
  else
    archive="nimble.tar.gz"
  fi

  download_url=$(asset_url_for "$want_arch")
  info "Downloading from: ${download_url}"

  if ! curl -fsSL "${download_url}" -o "$archive"; then
    rm -f "$archive"

    if [[ "$want_arch" = "x64" ]]; then
      err "No prebuilt nimble at ${download_url}"
      err "Resolution confirms a tag exists, but not that it published binaries;"
      err "early nimble releases have none. Try a newer version, or 'latest'."
      exit 1
    fi

    warn "nimble ${nimble_version} publishes no ${want_arch} binary for this" \
      "platform; installing the x64 one instead. It will run emulated, and" \
      "nimble will resolve an x64 Nim, so NimScript will report amd64. Use a" \
      "newer nimble, or a commit-ish pin, to get a native build."

    want_arch="x64"
    download_url=$(asset_url_for "$want_arch")
    info "Downloading from: ${download_url}"
    if ! curl -fsSL "${download_url}" -o "$archive"; then
      err "No prebuilt nimble at ${download_url}"
      rm -f "$archive"
      exit 1
    fi
  fi

  mkdir -p "${nimble_install_dir}/bin"

  if [[ "$os" = "Windows" ]]; then
    install_windows_certs
    # Try the new structure (direct exe)
    unzip -j -o "$archive" "nimble.exe" -d "${nimble_install_dir}/bin" ||
      # If that fails, try the old structure (nested exe)
      unzip -j -o "$archive" "*/nimble.exe" -d "${nimble_install_dir}/bin"
  else
    tar xzf "$archive" -C "${nimble_install_dir}/bin"
  fi
  rm -f "$archive"

  if [[ ! -f "${nimble_install_dir}/bin/nimble" && ! -f "${nimble_install_dir}/bin/nimble.exe" ]]; then
    err "The archive at ${download_url} contained no nimble binary"
    exit 1
  fi
}

build_from_source() {
  local nim_cmd src_dir out_bin

  if ! nim_cmd=$(find_nim); then
    err "Building nimble from a commit needs a Nim compiler, and none was found."
    err "Add a Nim setup step before this action, or let the action fetch one."
    exit 1
  fi
  info "Building with nim: ${nim_cmd}"

  if [[ "$os" = "Windows" ]]; then
    ensure_c_compiler
    # nim.exe is a native binary, so this MSYS-style path only works because
    # MSYS2 rewrites it to D:/... when spawning a native process. Do not
    # "simplify" it to a bare relative path; nim resolves -o: against its own cwd.
    out_bin="${PWD}/${nimble_install_dir}/bin/nimble.exe"
  else
    out_bin="${PWD}/${nimble_install_dir}/bin/nimble"
  fi

  src_dir="${source_dir}"
  rm -rf "$src_dir"
  mkdir -p "$src_dir"

  mkdir -p "$(dirname "$out_bin")"

  info "Fetching nimble at ${nimble_sha}..."
  (
    cd "$src_dir"
    git init -q
    git remote add origin "$NIMBLE_REPO_URL"
    # Fetching the resolved SHA directly keeps the download to a single commit,
    # whether the user asked for a SHA, a branch or a tag.
    git fetch -q --depth 1 origin "$nimble_sha"
    git checkout -q FETCH_HEAD
    # nimble vendors every dependency as a submodule, so this is the whole of
    # dependency resolution.
    # chronos and bearssl nest deeply enough to pass MAX_PATH on Windows unless
    # long paths are enabled, and core.longpaths is not set on the runner images.
    git -c core.longpaths=true submodule update -q --init --recursive --depth 1

    info "Compiling nimble (this takes a few minutes)..."
    "$nim_cmd" c -d:release --hints:off -o:"$out_bin" src/nimble.nim
  )

  rm -rf "$src_dir"

  if [[ ! -f "$out_bin" ]]; then
    err "The build reported success but ${out_bin} is missing"
    exit 1
  fi

  if [[ "$os" = "Windows" ]]; then
    install_windows_certs
  fi
}

# parse commandline args
kind="release"
nimble_version=""
nimble_sha=""
nimble_install_dir=".nimble_runtime"
os="Linux"
parent_nimble_install_dir=""
nim_bootstrap_dir=""
source_dir=""
# Defaults to the host arch so the script stays usable outside Actions; the
# action passes runner.arch explicitly.
nimble_arch="$(uname -m)"
release_tag=""

while ((0 < $#)); do
  opt=$1
  shift
  case $opt in
  --kind)
    kind=$1
    shift
    ;;
  --nimble-version)
    nimble_version=$1
    shift
    ;;
  --nimble-sha)
    nimble_sha=$1
    shift
    ;;
  --nimble-install-directory)
    nimble_install_dir=$1
    shift
    ;;
  --parent-nimble-install-directory)
    parent_nimble_install_dir=$1
    shift
    ;;
  --nim-bootstrap-directory)
    nim_bootstrap_dir=$1
    shift
    ;;
  --source-directory)
    source_dir=$1
    shift
    ;;
  --os)
    os=$1
    shift
    ;;
  --arch)
    nimble_arch=$1
    shift
    ;;
  *)
    err "Unknown option '${opt}'"
    exit 1
    ;;
  esac
done

if [[ "$parent_nimble_install_dir" = "" ]]; then
  parent_nimble_install_dir="$PWD"
fi

cd "$parent_nimble_install_dir"

info "Current directory: $(pwd)"
info "Installing to: ${nimble_install_dir}/bin"

case "$kind" in
release)
  info "Installing nimble ${nimble_version}"
  download_release
  ;;
source)
  if [[ -z "$nimble_sha" ]]; then
    err "--nimble-sha is required when --kind is 'source'"
    exit 1
  fi
  # Deliberately NOT created up front: actions/cache saves in the post phase even
  # when the job failed, so an empty bin/ left behind by a failed build would be
  # cached against this SHA and skip the install on every later run.
  if [[ -z "$source_dir" ]]; then
    err "--source-directory is required when --kind is 'source'"
    exit 1
  fi
  info "Installing nimble from commit ${nimble_sha} (${nimble_version})"
  build_from_source
  ;;
*)
  err "Unknown --kind '${kind}'"
  exit 1
  ;;
esac

info "Contents of ${nimble_install_dir}/bin:"
ls -la "${nimble_install_dir}/bin"

# The whole point of the arch handling above is that a mismatch should never be
# something you discover later by running `file` on a build artefact.
installed_bin="${nimble_install_dir}/bin/nimble"
if [[ ! -f "$installed_bin" ]]; then
  installed_bin="${nimble_install_dir}/bin/nimble.exe"
fi
if command -v file > /dev/null 2>&1 && [[ -f "$installed_bin" ]]; then
  info "Installed binary: $(file -b "$installed_bin")"
fi

info "Nimble installation complete"
