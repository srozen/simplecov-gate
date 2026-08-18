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
  def run_gate(minimum:, files: {}, env: {})
    Dir.mktmpdir do |dir|
      files.each { |name, content| File.write(File.join(dir, name), content) }
      stdout = StringIO.new
      full_env = {
        "SIMPLECOV_GATE_MINIMUM_COVERAGE" => minimum,
        "SIMPLECOV_GATE_COVERAGE_PATH" => dir
      }.merge(env)

      status = SimplecovGate::CLI.run(env: full_env, stdout: stdout)
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
