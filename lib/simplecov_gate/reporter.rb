# frozen_string_literal: true

module SimplecovGate
  # Reports through every GitHub surface: the workflow log, error
  # annotations, the step summary and the dedicated check run. Each
  # criterion gets its own line; the check run carries them all.
  class Reporter
    def initialize(stdout:, check_run:, summary_path:)
      @stdout = stdout
      @check_run = check_run
      @summary_path = summary_path
    end

    def verdict(verdict)
      verdict.results.each { |result| announce(result) }
      summarize(verdict.results.map { |result| "#{icon(result.passed?)} #{result.message}" })
      @check_run.publish(conclusion: verdict.conclusion, title: verdict.message)
    end

    def failure(message)
      @stdout.puts "::error::#{message}"
      summarize(["#{icon(false)} #{message}"])
      @check_run.publish(conclusion: "failure", title: message)
    end

    private

    def announce(result)
      @stdout.puts result.message
      @stdout.puts "::error::#{result.message}" unless result.passed?
    end

    def icon(passed)
      passed ? ":white_check_mark:" : ":x:"
    end

    def summarize(lines)
      return unless @summary_path

      File.open(@summary_path, "a") { |summary| summary.puts("### SimpleCov Gate\n\n#{lines.join("\n")}") }
    end
  end
end
