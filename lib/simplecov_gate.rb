# frozen_string_literal: true

require "json"
require "net/http"

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

  # Publishes the verdict as a dedicated check run on the pull request,
  # named after the action. Cosmetic by design: any hiccup surfaces as a
  # workflow warning and never fails the gate.
  class CheckRun
    NAME = "SimpleCov Gate"
    TOKEN = "SIMPLECOV_GATE_GITHUB_TOKEN"

    def initialize(env:, stdout:, transport: Net::HTTP.method(:post))
      @env = env
      @stdout = stdout
      @transport = transport
    end

    def publish(conclusion:, title:)
      return if token.empty? || repository.empty?

      response = @transport.call(uri, JSON.generate(payload(conclusion, title)), headers)
      return if response.code.start_with?("2")

      warn_failure("GitHub responded with #{response.code}; grant the workflow `checks: write` permission")
    rescue StandardError => e
      warn_failure(e.message)
    end

    private

    def token
      @env[TOKEN].to_s
    end

    def repository
      @env["GITHUB_REPOSITORY"].to_s
    end

    def uri
      URI("#{@env.fetch('GITHUB_API_URL', 'https://api.github.com')}/repos/#{repository}/check-runs")
    end

    def headers
      {
        "Authorization" => "Bearer #{token}",
        "Accept" => "application/vnd.github+json",
        "X-GitHub-Api-Version" => "2022-11-28",
        "Content-Type" => "application/json"
      }
    end

    def payload(conclusion, title)
      {
        name: NAME,
        head_sha: head_sha,
        status: "completed",
        conclusion: conclusion,
        output: { title: title, summary: title }
      }
    end

    # On pull_request events GITHUB_SHA points to the synthetic merge
    # commit, whose check runs would not surface on the pull request, so
    # prefer the head of the pull request from the event payload.
    def head_sha
      event.dig("pull_request", "head", "sha") || @env["GITHUB_SHA"]
    end

    def event
      path = @env["GITHUB_EVENT_PATH"].to_s
      File.file?(path) ? JSON.parse(File.read(path)) : {}
    end

    def warn_failure(reason)
      @stdout.puts "::warning::Could not create the '#{NAME}' check run: #{reason}."
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
      report(result)
      result.passed? ? 0 : 1
    rescue Error => e
      @stdout.puts "::error::#{e.message}"
      summarize ":x: #{e.message}"
      @check_run.publish(conclusion: "failure", title: e.message)
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
      @check_run.publish(conclusion: passed ? "success" : "failure", title: message)
    end

    def summarize(line)
      path = @env[STEP_SUMMARY]
      return unless path

      File.open(path, "a") { |summary| summary.puts("### SimpleCov Gate\n\n#{line}") }
    end
  end
end
