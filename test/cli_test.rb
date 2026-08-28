# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# Turning the action's inputs into a run: which minimums are configured,
# where the report is looked for, and the exit status that comes back.
class CLITest < GateTest
  # An input the caller left out reaches the script as an empty string,
  # and the workflow expression for a blank input can leave whitespace.
  def test_treats_a_blank_criterion_input_as_unconfigured
    files = { "coverage.json" => coverage_json(97.5) }
    status, output = run_gate(files: files, minimum: "90", branch_minimum: "  ")

    assert_equal 0, status
    refute_includes output, "Branch coverage"
  end

  def test_requires_at_least_one_coverage_minimum
    status, output = run_gate(files: { "coverage.json" => coverage_json(100) })

    assert_equal 1, status
    assert_includes output, "::error::Set at least one coverage minimum: " \
                            "minimum-coverage, minimum-branch-coverage, minimum-method-coverage."
  end

  def test_rejects_a_non_numeric_minimum
    status, output = run_gate(files: { "coverage.json" => coverage_json(100) }, minimum: "high")

    assert_equal 1, status
    assert_includes output, "::error::minimum-coverage must be a number between 0 and 100, got 'high'"
  end

  def test_rejects_a_minimum_out_of_range
    status, output = run_gate(files: { "coverage.json" => coverage_json(100) }, minimum: "150")

    assert_equal 1, status
    assert_includes output, "got '150'"
  end

  def test_names_the_offending_input_when_a_criterion_minimum_is_invalid
    status, output = run_gate(files: { "coverage.json" => coverage_json(100) }, branch_minimum: "lots")

    assert_equal 1, status
    assert_includes output, "::error::minimum-branch-coverage must be a number between 0 and 100, got 'lots'"
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
end
