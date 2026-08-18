# frozen_string_literal: true

module SimplecovGate
  # Adapts the GitHub Actions environment to the Gate: reads the action's
  # inputs from ENV, reports the verdict and turns it into an exit status.
  class CLI
    MINIMUM_COVERAGE = "SIMPLECOV_GATE_MINIMUM_COVERAGE"
    COVERAGE_PATH = "SIMPLECOV_GATE_COVERAGE_PATH"
    STEP_SUMMARY = "GITHUB_STEP_SUMMARY"
    DEFAULT_COVERAGE_PATH = "coverage"

    def self.run(env: ENV, stdout: $stdout, check_run: CheckRun.new(env: env, stdout: stdout))
      new(env: env, stdout: stdout, check_run: check_run).call
    end

    def initialize(env:, stdout:, check_run:)
      @env = env
      @stdout = stdout
      @check_run = check_run
    end

    def call
      result = Gate.new(minimum: minimum, coverage_path: coverage_path).check
      reporter.verdict(result)
      result.passed? ? 0 : 1
    rescue Error => e
      reporter.failure(e.message)
      1
    end

    private

    def minimum
      raw = @env[MINIMUM_COVERAGE].to_s
      minimum = Float(raw, exception: false)
      unless minimum&.between?(0, 100)
        raise Error, "minimum-coverage must be a number between 0 and 100, got '#{raw}'"
      end

      minimum
    end

    def coverage_path
      path = @env[COVERAGE_PATH].to_s
      path.empty? ? DEFAULT_COVERAGE_PATH : path
    end

    def reporter
      @reporter ||= Reporter.new(stdout: @stdout, check_run: @check_run, summary_path: @env[STEP_SUMMARY])
    end
  end
end
