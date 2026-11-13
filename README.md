# setup-nimble-action

![Build Status](https://github.com/nim-lang/setup-nimble-action/workflows/build/badge.svg)

This action sets up [Nimble](https://github.com/nim-lang/nimble) (Nim's package manager) in your GitHub Actions workflow.

## Usage

See [action.yml](action.yml)

### Basic usage

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: nim-lang/setup-nimble-action@v2
    with:
      nimble-version: '0.16.4' # default is 'latest'. You could also use `nightly` to get #HEAD
      repo-token: ${{ secrets.GITHUB_TOKEN }}
```

`repo-token` is used for [Rate limiting](https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting).
It works without setting this parameter, but please set it if you get rate limit errors.

### Versions

`@v2` is the current major version. `@v1` is frozen and still works, so existing
workflows keep running unchanged until you choose to move.

Two things changed in v2:

- Nimble is installed for the runner's architecture, so Apple Silicon runners get a
  native arm64 binary instead of an emulated x86_64 one. **If a macOS job builds for
  an architecture other than the runner's own, pass the target explicitly** — for
  example `--passC:"-target x86_64-apple-macos11"` alongside `--cpu:amd64`.
- `nimble-version` accepts a commit SHA or branch name, built from source.

### Architecture

The action installs a Nimble matching the runner's architecture, so Apple Silicon
and arm64 Linux runners get a native binary rather than an emulated x86_64 one.

Nimble does not publish a native binary for every architecture on every release —
`macosx_aarch64` starts at 0.22.2, and Windows has no arm64 build. Where one is
missing the action installs the x64 binary and emits a warning annotation, since
an emulated Nimble goes on to resolve an x64 Nim, which makes NimScript report
`amd64` on an arm64 machine.

### Pin to a commit or branch

`nimble-version` also accepts a commit SHA or a branch name from
[nim-lang/nimble](https://github.com/nim-lang/nimble). These are built from
source: expect a few minutes on a cold cache (the result is cached per commit),
and a Nim compiler is downloaded for the build unless `nim` is already on `PATH`.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: nim-lang/setup-nimble-action@v2
    with:
      nimble-version: 'a1b471d13d173897942f99d013f4efb79913bdf2' # or a branch, e.g. 'master'
      repo-token: ${{ secrets.GITHUB_TOKEN }}
```

### Verify the downloaded release

Set `nimble-sha256` to the expected SHA-256 of the release archive, and the
action fails before extracting anything that doesn't match. The archive differs
per OS and architecture, so pin an exact version and give each matrix entry its
own hash. GitHub shows each asset's digest on the
[release page](https://github.com/nim-lang/nimble/releases), and the action
logs the hash of every archive it downloads. A commit-ish needs no hash: its
commit SHA already pins it. The pin covers the nimble archive only; on Windows,
the CA bundle (`cacert.pem`) and the Nim DLLs are still downloaded unpinned.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: nim-lang/setup-nimble-action@v2
    with:
      nimble-version: '0.26.2'
      # nimble-linux_x64.tar.gz, for a Linux x64 runner
      nimble-sha256: 'sha256:facaf75407ea8cc4bb6b862a3299efa90ac57e05faa9e498402d0950e9d5cd2a'
      repo-token: ${{ secrets.GITHUB_TOKEN }}
```

### Setup latest version

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: nim-lang/setup-nimble-action@v2
    with:
      nimble-version: 'latest'
      repo-token: ${{ secrets.GITHUB_TOKEN }}
```

### Cache usage

```yaml
steps:
  - uses: actions/checkout@v4
  - name: Cache nimble
    id: cache-nimble
    uses: actions/cache@v4
    with:
      path: ~/.nimble
      key: ${{ runner.os }}-nimble-${{ hashFiles('*.nimble') }}
      restore-keys: |
        ${{ runner.os }}-nimble-
    if: runner.os != 'Windows'
  - uses: nim-lang/setup-nimble-action@v2
    with:
      repo-token: ${{ secrets.GITHUB_TOKEN }}
```

### Matrix testing usage

Test across multiple platforms:

```yaml
jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os:
          - ubuntu-latest
          - windows-latest
          - macOS-latest
    steps:
      - uses: actions/checkout@v4
      - uses: nim-lang/setup-nimble-action@v2
        with:
          repo-token: ${{ secrets.GITHUB_TOKEN }}
```

### Change Nimble installation directory

The action installs Nimble to `.nimble_runtime` directory by default. You can change this using:

```yaml
  - uses: nim-lang/setup-nimble-action@v2
    with:
      nimble-version: latest
      repo-token: ${{ secrets.GITHUB_TOKEN }}
      nimble-install-directory: custom_dir
```

## License

MIT

