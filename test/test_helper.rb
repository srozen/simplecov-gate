# frozen_string_literal: true

require "simplecov"
# Filter explicitly: unlike 1.0+, SimpleCov 0.x tracks everything under
# root, and the CI matrix runs this suite against 0.x too — where `skip`
# does not exist yet (1.1 renamed `add_filter` to `skip`).
SimpleCov.public_send(SimpleCov.respond_to?(:skip) ? :skip : :add_filter, ["/test/", "/vendor/"])
SimpleCov.start

require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "../lib/simplecov_gate"

# Base class for the suite: builds SimpleCov reports to gate against and
# runs the CLI over them, so each test names only what it is about.
class GateTest < Minitest::Test
  private

  # A coverage.json carrying exactly the criteria it was given, with the
  # `meta` flags SimpleCov writes to record which ones it tracked.
  def coverage_json(line = nil, branch: nil, method: nil)
    percentages = { "lines" => line, "branches" => branch, "methods" => method }.compact
    JSON.generate(
      "meta" => { "schema_version" => "1.0", "line_coverage" => !line.nil?,
                  "branch_coverage" => !branch.nil?, "method_coverage" => !method.nil? },
      "total" => percentages.transform_values { |percent| { "percent" => percent } }
    )
  end

  # Runs the CLI against a temporary coverage directory holding +files+,
  # returning the exit status and everything written to stdout.
  def run_gate(files: {}, env: {}, check_run: nil, minimum: nil, branch_minimum: nil, method_minimum: nil)
    Dir.mktmpdir do |dir|
      files.each { |name, content| File.write(File.join(dir, name), content) }
      stdout = StringIO.new
      full_env = {
        "SIMPLECOV_GATE_MINIMUM_COVERAGE" => minimum,
        "SIMPLECOV_GATE_MINIMUM_BRANCH_COVERAGE" => branch_minimum,
        "SIMPLECOV_GATE_MINIMUM_METHOD_COVERAGE" => method_minimum,
        "SIMPLECOV_GATE_COVERAGE_PATH" => dir
      }.merge(env)
      options = { env: full_env, stdout: stdout }
      options[:check_run] = check_run if check_run

      status = SimplecovGate::CLI.run(**options)
      [status, stdout.string]
    end
  end
end
