# frozen_string_literal: true

require "json"

# Gates a build on the total line coverage reported by SimpleCov.
module SimplecovGate
  Error = Class.new(StandardError)

  # The verdict of comparing a coverage percentage against a minimum.
  Result = Struct.new(:percent, :minimum) do
    def passed?
      percent >= minimum
    end
  end

  # Extracts the total line coverage from a SimpleCov report and compares
  # it against a minimum percentage.
  #
  # Reads coverage.json, written by default since SimpleCov 1.0, and falls
  # back to .last_run.json for older versions. The percentage is floored
  # to two decimals, mirroring SimpleCov's own strictness.
  class Gate
    REPORTS = {
      "coverage.json" => ->(data) { data.dig("total", "lines", "percent") },
      ".last_run.json" => ->(data) { data.dig("result", "line") || data.dig("result", "covered_percent") }
    }.freeze

    def initialize(minimum:, coverage_path:)
      @minimum = minimum
      @coverage_path = coverage_path
    end

    def check
      Result.new(covered_percent, @minimum)
    end

    private

    def covered_percent
      path = report_path
      percent = extract(path)
      unless percent.is_a?(Numeric)
        raise Error, "#{path} does not contain a total line coverage percentage; is it a SimpleCov report?"
      end

      percent.to_f.floor(2)
    end

    def report_path
      REPORTS.keys.map { |name| File.join(@coverage_path, name) }.find { |path| File.file?(path) } ||
        raise(Error, "No SimpleCov report (#{REPORTS.keys.join(' or ')}) found in '#{@coverage_path}'. " \
                     "Run the tests with SimpleCov enabled before this action, or point " \
                     "'coverage-path' at SimpleCov's coverage directory.")
    end

    def extract(path)
      REPORTS.fetch(File.basename(path)).call(parse(path))
    rescue TypeError
      nil
    end

    def parse(path)
      data = JSON.parse(File.read(path))
      raise Error, "#{path} is not a JSON object; is it a SimpleCov report?" unless data.is_a?(Hash)

      data
    rescue JSON::ParserError => e
      raise Error, "#{path} is not valid JSON: #{e.message}"
    end
  end

  # Adapts the GitHub Actions environment to the Gate: reads the action's
  # inputs from ENV, reports through the workflow log and the step summary,
  # and turns the verdict into an exit status.
  class CLI
    MINIMUM_COVERAGE = "SIMPLECOV_GATE_MINIMUM_COVERAGE"
    COVERAGE_PATH = "SIMPLECOV_GATE_COVERAGE_PATH"
    STEP_SUMMARY = "GITHUB_STEP_SUMMARY"
    DEFAULT_COVERAGE_PATH = "coverage"

    def self.run(env: ENV, stdout: $stdout)
      new(env: env, stdout: stdout).call
    end

    def initialize(env:, stdout:)
      @env = env
      @stdout = stdout
    end

    def call
      result = Gate.new(minimum: minimum, coverage_path: coverage_path).check
      report(result)
      result.passed? ? 0 : 1
    rescue Error => e
      @stdout.puts "::error::#{e.message}"
      summarize ":x: #{e.message}"
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

    def report(result)
      passed = result.passed?
      message = format("Line coverage %.2f%% %s the minimum %.2f%%",
                       result.percent, passed ? "meets" : "is below", result.minimum)
      @stdout.puts message
      @stdout.puts "::error::#{message}" unless passed
      summarize "#{passed ? ':white_check_mark:' : ':x:'} #{message}"
    end

    def summarize(line)
      path = @env[STEP_SUMMARY]
      return unless path

      File.open(path, "a") { |summary| summary.puts("### SimpleCov Gate\n\n#{line}") }
    end
  end
end
