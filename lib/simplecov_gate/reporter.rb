# frozen_string_literal: true

module SimplecovGate
  # Reports through every GitHub surface: the workflow log, error
  # annotations, the step summary and the dedicated check run.
  class Reporter
    def initialize(stdout:, check_run:, summary_path:)
      @stdout = stdout
      @check_run = check_run
      @summary_path = summary_path
    end

    def verdict(result)
      @stdout.puts result.message
      @stdout.puts "::error::#{result.message}" unless result.passed?
      summarize(result.passed? ? ":white_check_mark:" : ":x:", result.message)
      @check_run.publish(conclusion: result.conclusion, title: result.message)
    end

    def failure(message)
      @stdout.puts "::error::#{message}"
      summarize(":x:", message)
      @check_run.publish(conclusion: "failure", title: message)
    end

    private

    def summarize(icon, message)
      return unless @summary_path

      File.open(@summary_path, "a") { |summary| summary.puts("### SimpleCov Gate\n\n#{icon} #{message}") }
    end
  end
end
