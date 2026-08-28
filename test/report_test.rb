# frozen_string_literal: true

require_relative "test_helper"

# Reading SimpleCov's own output: which report file is used, the formats
# each version writes, and what a report that cannot answer looks like.
class ReportTest < GateTest
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

  def test_falls_back_to_last_run_json_for_branch_coverage
    files = { ".last_run.json" => %({"result":{"line":88.4,"branch":72.0}}) }
    status, output = run_gate(files: files, minimum: "88", branch_minimum: "80")

    assert_equal 1, status
    assert_includes output, "Line coverage 88.40% meets the minimum 88.00%"
    assert_includes output, "::error::Branch coverage 72.00% is below the minimum 80.00%"
  end

  def test_falls_back_to_last_run_json_for_method_coverage
    status, output = run_gate(files: { ".last_run.json" => %({"result":{"method":66.0}}) }, method_minimum: "60")

    assert_equal 0, status
    assert_includes output, "Method coverage 66.00% meets the minimum 60.00%"
  end

  # `covered_percent` is the pre-0.18 spelling of line coverage alone —
  # it must never stand in for another criterion.
  def test_the_legacy_last_run_percentage_is_line_coverage_only
    status, output = run_gate(files: { ".last_run.json" => %({"result":{"covered_percent":76.1}}) },
                              branch_minimum: "60")

    assert_equal 1, status
    assert_includes output, "does not contain a total branch coverage percentage"
  end

  def test_explains_a_criterion_simplecov_did_not_track
    status, output = run_gate(files: { "coverage.json" => coverage_json(97.5) }, branch_minimum: "80")

    assert_equal 1, status
    assert_includes output, "reports no branch coverage: SimpleCov did not track it in this run"
    assert_includes output, "enable_coverage :branch"
    assert_includes output, "drop the 'minimum-branch-coverage' input"
  end

  # A branch-only run writes a coverage.json with no `total.lines` at
  # all, which is a valid report, not a malformed one.
  def test_explains_a_line_only_gate_against_a_branch_only_report
    status, output = run_gate(files: { "coverage.json" => coverage_json(nil, branch: 90.0) }, minimum: "90")

    assert_equal 1, status
    assert_includes output, "reports no line coverage: SimpleCov did not track it in this run"
    assert_includes output, "drop the 'minimum-coverage' input"
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
end
