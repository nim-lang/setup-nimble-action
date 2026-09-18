# setup-nimble-action

![Build Status](https://github.com/nim-lang/setup-nimble-action/workflows/build/badge.svg)

This action sets up [Nimble](https://github.com/nim-lang/nimble) (Nim's package manager) in your GitHub Actions workflow.

## Usage

See [action.yml](action.yml)

### Basic usage

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: nim-lang/setup-nimble-action@v1
    with:
      nimble-version: '0.16.4' # default is 'latest'. You could also use `nightly` to get #HEAD
      repo-token: ${{ secrets.GITHUB_TOKEN }}
```

`repo-token` is used for [Rate limiting](https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting).
It works without setting this parameter, but please set it if you get rate limit errors.

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
  - uses: nim-lang/setup-nimble-action@v1
    with:
      nimble-version: 'a1b471d13d173897942f99d013f4efb79913bdf2' # or a branch, e.g. 'master'
      repo-token: ${{ secrets.GITHUB_TOKEN }}
```

### Setup latest version

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: nim-lang/setup-nimble-action@v1
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
  - uses: nim-lang/setup-nimble-action@v1
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
      - uses: nim-lang/setup-nimble-action@v1
        with:
          repo-token: ${{ secrets.GITHUB_TOKEN }}
```

### Change Nimble installation directory

The action installs Nimble to `.nimble_runtime` directory by default. You can change this using:

```yaml
  - uses: nim-lang/setup-nimble-action@v1
    with:
      nimble-version: latest
      repo-token: ${{ secrets.GITHUB_TOKEN }}
      nimble-install-directory: custom_dir
```

## License

MIT

