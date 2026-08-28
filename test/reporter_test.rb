# frozen_string_literal: true

require_relative "test_helper"

# What the run leaves behind on the job's step summary.
class ReporterTest < GateTest
  def test_appends_a_passing_step_summary
    summary = with_step_summary(files: { "coverage.json" => coverage_json(100) }, minimum: "100")

    assert_includes summary, "### SimpleCov Gate"
    assert_includes summary, ":white_check_mark: Line coverage 100.00% meets the minimum 100.00%"
  end

  def test_appends_a_failing_step_summary
    summary = with_step_summary(files: { "coverage.json" => coverage_json(50) }, minimum: "100")

    assert_includes summary, ":x: Line coverage 50.00% is below the minimum 100.00%"
  end

  def test_appends_one_line_per_criterion_under_one_heading
    files = { "coverage.json" => coverage_json(100, branch: 50.0) }
    summary = with_step_summary(files: files, minimum: "100", branch_minimum: "80")

    assert_equal 1, summary.scan("### SimpleCov Gate").size
    assert_includes summary, ":white_check_mark: Line coverage 100.00% meets the minimum 100.00%\n" \
                             ":x: Branch coverage 50.00% is below the minimum 80.00%"
  end

  def test_appends_an_error_step_summary
    summary = with_step_summary(minimum: "100")

    assert_includes summary, ":x: No SimpleCov report"
  end

  private

  def with_step_summary(**options)
    Dir.mktmpdir do |dir|
      summary_path = File.join(dir, "step_summary.md")
      run_gate(env: { "GITHUB_STEP_SUMMARY" => summary_path }, **options)
      File.read(summary_path)
    end
  end
end
