# frozen_string_literal: true

require_relative "test_helper"

# The verdict itself: each configured criterion compared against its
# minimum, and the pass/fail that follows.
class GateVerdictTest < GateTest
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

  def test_gates_branch_coverage
    files = { "coverage.json" => coverage_json(97.5, branch: 84.0) }
    status, output = run_gate(files: files, branch_minimum: "80")

    assert_equal 0, status
    assert_includes output, "Branch coverage 84.00% meets the minimum 80.00%"
  end

  def test_fails_below_the_branch_minimum
    files = { "coverage.json" => coverage_json(97.5, branch: 71.25) }
    status, output = run_gate(files: files, branch_minimum: "80")

    assert_equal 1, status
    assert_includes output, "::error::Branch coverage 71.25% is below the minimum 80.00%"
  end

  def test_gates_method_coverage
    files = { "coverage.json" => coverage_json(97.5, method: 100.0) }
    status, output = run_gate(files: files, method_minimum: "100")

    assert_equal 0, status
    assert_includes output, "Method coverage 100.00% meets the minimum 100.00%"
  end

  def test_floors_branch_coverage_like_line_coverage
    files = { "coverage.json" => coverage_json(100, branch: 94.999) }
    status, output = run_gate(files: files, branch_minimum: "95")

    assert_equal 1, status
    assert_includes output, "Branch coverage 94.99%"
  end

  def test_gates_every_criterion_at_once
    files = { "coverage.json" => coverage_json(97.5, branch: 84.0, method: 91.0) }
    status, output = run_gate(files: files, minimum: "90", branch_minimum: "80", method_minimum: "90")

    assert_equal 0, status
    assert_equal ["Line coverage 97.50% meets the minimum 90.00%",
                  "Branch coverage 84.00% meets the minimum 80.00%",
                  "Method coverage 91.00% meets the minimum 90.00%"], output.lines.map(&:chomp)
  end

  def test_fails_when_any_single_criterion_is_below_its_minimum
    files = { "coverage.json" => coverage_json(97.5, branch: 71.0) }
    status, output = run_gate(files: files, minimum: "90", branch_minimum: "80")

    assert_equal 1, status
    assert_includes output, "Line coverage 97.50% meets the minimum 90.00%"
    assert_includes output, "::error::Branch coverage 71.00% is below the minimum 80.00%"
    refute_includes output, "::error::Line"
  end

  def test_gates_only_the_criteria_that_were_configured
    files = { "coverage.json" => coverage_json(97.5, branch: 10.0, method: 10.0) }
    status, output = run_gate(files: files, minimum: "90")

    assert_equal 0, status
    refute_includes output, "Branch coverage"
    refute_includes output, "Method coverage"
  end
end
