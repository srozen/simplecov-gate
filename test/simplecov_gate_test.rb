# frozen_string_literal: true

require "simplecov"
# Filter explicitly: unlike 1.0+, SimpleCov 0.x tracks everything under
# root, and the CI matrix runs this suite against 0.x too — where `skip`
# does not exist yet (1.1 renamed `add_filter` to `skip`).
SimpleCov.public_send(SimpleCov.respond_to?(:skip) ? :skip : :add_filter, ["/test/", "/vendor/"])
SimpleCov.start

require "minitest/autorun"
require "open3"
require "stringio"
require "tmpdir"
require_relative "../lib/simplecov_gate"

class SimplecovGateTest < Minitest::Test
  def test_passes_when_coverage_meets_the_minimum
    status, output = run_gate(files: { "coverage.json" => coverage_json(97.5) }, minimum: "90")

    assert_equal 0, status
    assert_includes output, "Line coverage 97.50% meets the minimum 90.00%"
    refute_includes output, "::error::"
  end

  def test_passes_on_the_exact_minimum
    status, = run_gate(files: { "coverage.json" => coverage_json(100) }, minimum: "100")

    assert_equal 0, status
  end

  def test_fails_below_the_minimum_with_an_error_annotation
    status, output = run_gate(files: { "coverage.json" => coverage_json(80.0) }, minimum: "90")

    assert_equal 1, status
    assert_includes output, "::error::Line coverage 80.00% is below the minimum 90.00%"
  end

  def test_floors_the_percentage_instead_of_rounding
    status, output = run_gate(files: { "coverage.json" => coverage_json(94.999) }, minimum: "95")

    assert_equal 1, status
    assert_includes output, "94.99%"
  end

  def test_falls_back_to_last_run_json
    status, output = run_gate(files: { ".last_run.json" => %({"result":{"line":88.4}}) }, minimum: "88")

    assert_equal 0, status
    assert_includes output, "88.40%"
  end

  def test_reads_the_pre_simplecov_018_last_run_format
    status, output = run_gate(files: { ".last_run.json" => %({"result":{"covered_percent":76.1}}) }, minimum: "90")

    assert_equal 1, status
    assert_includes output, "76.10%"
  end

  def test_prefers_coverage_json_over_last_run_json
    files = { "coverage.json" => coverage_json(91.0), ".last_run.json" => %({"result":{"line":42.0}}) }
    status, output = run_gate(files: files, minimum: "90")

    assert_equal 0, status
    assert_includes output, "91.00%"
  end

  def test_fails_with_guidance_when_no_report_exists
    status, output = run_gate(minimum: "90")

    assert_equal 1, status
    assert_includes output, "::error::No SimpleCov report (coverage.json or .last_run.json) found"
  end

  def test_fails_on_malformed_json
    status, output = run_gate(files: { "coverage.json" => "{ not json" }, minimum: "90")

    assert_equal 1, status
    assert_includes output, "is not valid JSON"
  end

  def test_fails_when_the_report_lacks_a_total_percentage
    status, output = run_gate(files: { "coverage.json" => %({"total":{}}) }, minimum: "90")

    assert_equal 1, status
    assert_includes output, "does not contain a total line coverage"
  end

  def test_fails_when_the_report_has_an_unexpected_structure
    status, output = run_gate(files: { "coverage.json" => %({"total":5}) }, minimum: "90")

    assert_equal 1, status
    assert_includes output, "does not contain a total line coverage"
  end

  def test_fails_when_the_report_is_not_a_json_object
    status, output = run_gate(files: { "coverage.json" => "null" }, minimum: "90")

    assert_equal 1, status
    assert_includes output, "is not a JSON object"
  end

  def test_fails_when_the_last_run_report_lacks_a_percentage
    status, output = run_gate(files: { ".last_run.json" => %({"result":{}}) }, minimum: "90")

    assert_equal 1, status
    assert_includes output, "does not contain a total line coverage"
  end

  def test_rejects_a_missing_minimum
    status, output = run_gate(files: { "coverage.json" => coverage_json(100) }, minimum: nil)

    assert_equal 1, status
    assert_includes output, "::error::minimum-coverage must be a number between 0 and 100, got ''"
  end

  def test_rejects_a_non_numeric_minimum
    status, output = run_gate(files: { "coverage.json" => coverage_json(100) }, minimum: "high")

    assert_equal 1, status
    assert_includes output, "got 'high'"
  end

  def test_rejects_a_minimum_out_of_range
    status, output = run_gate(files: { "coverage.json" => coverage_json(100) }, minimum: "150")

    assert_equal 1, status
    assert_includes output, "got '150'"
  end

  def test_defaults_to_the_conventional_coverage_directory
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, "coverage"))
      File.write(File.join(dir, "coverage", "coverage.json"), coverage_json(100))

      status = Dir.chdir(dir) do
        SimplecovGate::CLI.run(env: { "SIMPLECOV_GATE_MINIMUM_COVERAGE" => "100" }, stdout: StringIO.new)
      end

      assert_equal 0, status
    end
  end

  def test_appends_a_passing_step_summary
    summary = with_step_summary(files: { "coverage.json" => coverage_json(100) }, minimum: "100")

    assert_includes summary, "### SimpleCov Gate"
    assert_includes summary, ":white_check_mark: Line coverage 100.00% meets the minimum 100.00%"
  end

  def test_appends_a_failing_step_summary
    summary = with_step_summary(files: { "coverage.json" => coverage_json(50) }, minimum: "100")

    assert_includes summary, ":x: Line coverage 50.00% is below the minimum 100.00%"
  end

  def test_appends_an_error_step_summary
    summary = with_step_summary(minimum: "100")

    assert_includes summary, ":x: No SimpleCov report"
  end

  def test_publishes_a_dedicated_check_run_with_the_verdict
    check_run = RecordingCheckRun.new
    run_gate(files: { "coverage.json" => coverage_json(100) }, minimum: "90", check_run: check_run)

    assert_equal [{ conclusion: "success", title: "Line coverage 100.00% meets the minimum 90.00%" }],
                 check_run.published
  end

  def test_publishes_a_failing_check_run_below_the_minimum
    check_run = RecordingCheckRun.new
    run_gate(files: { "coverage.json" => coverage_json(50) }, minimum: "90", check_run: check_run)

    assert_equal [{ conclusion: "failure", title: "Line coverage 50.00% is below the minimum 90.00%" }],
                 check_run.published
  end

  def test_publishes_a_failing_check_run_on_errors
    check_run = RecordingCheckRun.new
    run_gate(minimum: "90", check_run: check_run)

    assert_equal 1, check_run.published.size
    assert_equal "failure", check_run.published.first[:conclusion]
    assert_includes check_run.published.first[:title], "No SimpleCov report"
  end

  def test_check_run_posts_the_verdict_to_github
    requests = []
    stdout = StringIO.new
    check_run = github_check_run(stdout: stdout, transport: lambda { |uri, body, headers|
      requests << [uri.to_s, JSON.parse(body), headers]
      FakeResponse.new("201")
    })

    check_run.publish(conclusion: "success", title: "all good")

    uri, body, headers = requests.fetch(0)
    assert_equal "https://api.github.com/repos/acme/widgets/check-runs", uri
    assert_equal "SimpleCov Gate", body["name"]
    assert_equal "deadbeef", body["head_sha"]
    assert_equal "completed", body["status"]
    assert_equal "success", body["conclusion"]
    assert_equal "all good", body.dig("output", "title")
    assert_equal "Bearer s3cret", headers["Authorization"]
    assert_empty stdout.string
  end

  def test_check_run_prefers_the_pull_request_head_sha
    Dir.mktmpdir do |dir|
      event_path = File.join(dir, "event.json")
      File.write(event_path, %({"pull_request":{"head":{"sha":"cafe"}}}))
      requests = []
      check_run = github_check_run(env: { "GITHUB_EVENT_PATH" => event_path },
                                   transport: ->(_uri, body, _headers) { requests << JSON.parse(body); FakeResponse.new("201") })

      check_run.publish(conclusion: "success", title: "all good")

      assert_equal "cafe", requests.fetch(0).fetch("head_sha")
    end
  end

  def test_check_run_warns_when_github_declines
    stdout = StringIO.new
    check_run = github_check_run(stdout: stdout, transport: ->(*) { FakeResponse.new("403") })

    check_run.publish(conclusion: "success", title: "all good")

    assert_includes stdout.string, "::warning::Could not create the 'SimpleCov Gate' check run"
    assert_includes stdout.string, "checks: write"
  end

  def test_check_run_warns_instead_of_raising
    stdout = StringIO.new
    check_run = github_check_run(stdout: stdout, transport: ->(*) { raise "connection reset" })

    check_run.publish(conclusion: "success", title: "all good")

    assert_includes stdout.string, "connection reset"
  end

  def test_check_run_skips_quietly_without_a_token
    stdout = StringIO.new
    check_run = SimplecovGate::CheckRun.new(env: {}, stdout: stdout,
                                            transport: ->(*) { flunk "must not call GitHub" })

    check_run.publish(conclusion: "success", title: "all good")

    assert_empty stdout.string
  end

  def test_the_executable_wires_the_verdict_to_the_exit_status
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "coverage.json"), coverage_json(97.5))

      passing, passed = run_executable(dir, minimum: "90")
      failing, failed = run_executable(dir, minimum: "99")

      assert_predicate passed, :success?
      assert_includes passing, "97.50% meets the minimum 90.00%"
      assert_equal 1, failed.exitstatus
      assert_includes failing, "::error::"
    end
  end

  private

  FakeResponse = Struct.new(:code)

  class RecordingCheckRun
    attr_reader :published

    def initialize
      @published = []
    end

    def publish(**verdict)
      published << verdict
    end
  end

  def github_check_run(transport:, stdout: StringIO.new, env: {})
    full_env = {
      "SIMPLECOV_GATE_GITHUB_TOKEN" => "s3cret",
      "GITHUB_REPOSITORY" => "acme/widgets",
      "GITHUB_SHA" => "deadbeef"
    }.merge(env)
    SimplecovGate::CheckRun.new(env: full_env, stdout: stdout, transport: transport)
  end

  EXECUTABLE = File.expand_path("../bin/simplecov-gate", __dir__)

  def run_executable(coverage_dir, minimum:)
    env = {
      "SIMPLECOV_GATE_MINIMUM_COVERAGE" => minimum,
      "SIMPLECOV_GATE_COVERAGE_PATH" => coverage_dir,
      "GITHUB_STEP_SUMMARY" => nil
    }
    Open3.capture2e(env, RbConfig.ruby, EXECUTABLE)
  end

  def coverage_json(percent)
    JSON.generate("meta" => { "schema_version" => "1.1" }, "total" => { "lines" => { "percent" => percent } })
  end

  # Runs the CLI against a temporary coverage directory holding +files+,
  # returning the exit status and everything written to stdout.
  def run_gate(minimum:, files: {}, env: {}, check_run: nil)
    Dir.mktmpdir do |dir|
      files.each { |name, content| File.write(File.join(dir, name), content) }
      stdout = StringIO.new
      full_env = {
        "SIMPLECOV_GATE_MINIMUM_COVERAGE" => minimum,
        "SIMPLECOV_GATE_COVERAGE_PATH" => dir
      }.merge(env)
      options = { env: full_env, stdout: stdout }
      options[:check_run] = check_run if check_run

      status = SimplecovGate::CLI.run(**options)
      [status, stdout.string]
    end
  end

  def with_step_summary(**options)
    Dir.mktmpdir do |dir|
      summary_path = File.join(dir, "step_summary.md")
      run_gate(env: { "GITHUB_STEP_SUMMARY" => summary_path }, **options)
      File.read(summary_path)
    end
  end
end
