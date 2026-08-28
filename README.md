# SimpleCov Gate

A GitHub Action that fails the build when the coverage reported by
[SimpleCov](https://github.com/simplecov-ruby/simplecov) drops below a minimum
threshold. It gates line, branch and method coverage — the same criteria
SimpleCov itself can enforce.

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
Set `github-token: ""` to disable the check run.

## Coverage criteria

SimpleCov tracks line coverage by default and can additionally track branch
and method coverage. Each criterion the action gates has its own input, and
each one is independent — set the ones you want enforced and leave the rest
out:

```yaml
- name: Enforce coverage
  uses: srozen/simplecov-gate@v1
  with:
    minimum-coverage: 95         # line
    minimum-branch-coverage: 85
    minimum-method-coverage: 100
```

At least one of the three is required. Every criterion you set is checked, and
the gate fails if any of them falls short — the log and step summary carry one
line per criterion, so a single run tells you which one gave way.

Branch and method coverage have to be turned on in SimpleCov before there is
anything to gate:

```ruby
SimpleCov.start do
  enable_coverage :branch
  enable_coverage :method
end
```

If you gate a criterion SimpleCov did not track, the action says so and points
at the configuration rather than reporting a misleading failure.

**Version support.** Line coverage works on every SimpleCov version. Branch
coverage needs SimpleCov 0.18+ on CRuby 2.5+; method coverage needs SimpleCov
1.0+.

## Inputs

| Input                     | Required | Default        | Description                                                        |
| ------------------------- | -------- | -------------- | ------------------------------------------------------------------ |
| `minimum-coverage`        | see note | —              | Minimum required total line coverage, in percent (e.g. 90 or 99.5) |
| `minimum-branch-coverage` | no       | —              | Minimum required total branch coverage, in percent                 |
| `minimum-method-coverage` | no       | —              | Minimum required total method coverage, in percent                 |
| `coverage-path`           | no       | `coverage`     | Directory containing the SimpleCov report                          |
| `github-token`            | no       | `github.token` | Token used to publish the check run; empty string disables it      |

Note: no single minimum is required on its own, but at least one of the three
must be set.

## How it works

The action reads `coverage.json`, which SimpleCov writes to its coverage
directory by default since version 1.0, and takes the exact total percentage
SimpleCov reported for each criterion (`total.lines.percent`,
`total.branches.percent`, `total.methods.percent`). On older SimpleCov
versions it gracefully falls back to `.last_run.json`, covering both the
per-criterion `result.line` / `result.branch` format (0.18+) and the
line-only `result.covered_percent` format that preceded it.

The percentage is floored to two decimals — never rounded up — mirroring
SimpleCov's own strictness, so 94.999% does not pass a 95% gate.

## Development

```sh
bundle install
bundle exec ruby test/all.rb
```

`test/all.rb` loads the whole suite; each file under `test/` mirrors the part
of `lib/` it covers and runs on its own too:

| File                    | Covers                                                       |
| ----------------------- | ------------------------------------------------------------ |
| `gate_test.rb`          | the verdict: each criterion against its minimum              |
| `report_test.rb`        | reading SimpleCov's report formats, and their failure modes  |
| `cli_test.rb`           | inputs, report lookup, exit status                           |
| `reporter_test.rb`      | the job step summary                                         |
| `check_run_test.rb`     | the "SimpleCov Gate" check run and its GitHub call           |
| `criterion_test.rb`     | criteria staying in step with `action.yml`                   |

```sh
bundle exec ruby test/report_test.rb
```

This repository dogfoods itself: [CI](.github/workflows/ci.yml) runs the test
suite and then gates it with this very action at 100% line coverage.
