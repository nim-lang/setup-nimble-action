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
      nimble-version: '0.16.4' # default is 'latest'
      repo-token: ${{ secrets.GITHUB_TOKEN }}
```

`repo-token` is used for [Rate limiting](https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting).
It works without setting this parameter, but please set it if you get rate limit errors.

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

