# frozen_string_literal: true

module SimplecovGate
  # Adapts the GitHub Actions environment to the Gate: reads the action's
  # inputs from ENV, reports the verdict and turns it into an exit status.
  class CLI
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
      verdict = Gate.new(minimums: minimums, coverage_path: coverage_path).check
      reporter.verdict(verdict)
      verdict.passed? ? 0 : 1
    rescue Error => e
      reporter.failure(e.message)
      1
    end

    private

    # Every criterion is opt-in, mirroring SimpleCov, where each
    # threshold is configured on its own and disabled by default.
    def minimums
      minimums = Criterion::ALL.filter_map { |criterion| minimum_for(criterion) }
      raise Error, "Set at least one coverage minimum: #{Criterion::ALL.map(&:input).join(', ')}." if minimums.empty?

      minimums
    end

    def minimum_for(criterion)
      raw = @env[criterion.env].to_s
      return nil if raw.strip.empty?

      minimum = Float(raw, exception: false)
      unless minimum&.between?(0, 100)
        raise Error, "#{criterion.input} must be a number between 0 and 100, got '#{raw}'"
      end

      [criterion, minimum]
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
