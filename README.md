# SimpleCov Gate

A GitHub Action that fails the build when the total line coverage reported by
[SimpleCov](https://github.com/simplecov-ruby/simplecov) drops below a minimum
threshold.

It is a composite action running a single dependency-free Ruby script on the
runner's preinstalled Ruby — no `setup-ruby`, no gems to install, no container
to pull. It starts in milliseconds.

## Usage

Run your test suite with SimpleCov enabled, then add the gate:

```yaml
permissions:
  contents: read
  checks: write # lets the action publish its "SimpleCov Gate" check run

steps:
  - uses: actions/checkout@v4

  - name: Run tests
    run: bundle exec rake test

  - name: Enforce coverage
    uses: srozen/simplecov-gate@v1
    with:
      minimum-coverage: 95
```

The action reports the covered percentage and the minimum in the job log and
in the step summary, emits an `::error` annotation when the gate fails, and
publishes the verdict as a dedicated **SimpleCov Gate** check run listed
alongside your other checks on the pull request.

The check run needs the `checks: write` permission shown above; without it
the action prints a warning and the gate still passes or fails normally.
Set `github-token: ""` to disable the check run entirely.

## Inputs

| Input              | Required | Default    | Description                                                        |
| ------------------ | -------- | ---------- | ------------------------------------------------------------------ |
| `minimum-coverage` | yes      | —          | Minimum required total line coverage, in percent (e.g. 90 or 99.5) |
| `coverage-path`    | no       | `coverage` | Directory containing the SimpleCov report                          |
| `github-token`     | no       | `github.token` | Token used to publish the check run; empty string disables it  |

## How it works

The action reads `coverage.json`, which SimpleCov writes to its coverage
directory by default since version 1.0, and takes the exact total line
coverage SimpleCov reported (`total.lines.percent`). On older SimpleCov
versions it gracefully falls back to `.last_run.json`, covering both the
`result.line` (0.18+) and `result.covered_percent` (pre-0.18) formats.

The percentage is floored to two decimals — never rounded up — mirroring
SimpleCov's own strictness, so 94.999% does not pass a 95% gate.

## Development

```sh
bundle install
bundle exec ruby test/simplecov_gate_test.rb
```

This repository dogfoods itself: [CI](.github/workflows/ci.yml) runs the test
suite and then gates it with this very action at 100% line coverage.
