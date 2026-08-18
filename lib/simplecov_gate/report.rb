# frozen_string_literal: true

require "json"

module SimplecovGate
  # Extracts the total line coverage from a SimpleCov report.
  #
  # Reads coverage.json, written by default since SimpleCov 1.0, and falls
  # back to .last_run.json for older versions. The percentage is floored
  # to two decimals, mirroring SimpleCov's own strictness.
  class Report
    REPORTS = {
      "coverage.json" => ->(data) { data.dig("total", "lines", "percent") },
      ".last_run.json" => ->(data) { data.dig("result", "line") || data.dig("result", "covered_percent") }
    }.freeze

    def initialize(directory)
      @directory = directory
    end

    def percent
      path = report_path
      percent = extract(path)
      unless percent.is_a?(Numeric)
        raise Error, "#{path} does not contain a total line coverage percentage; is it a SimpleCov report?"
      end

      percent.to_f.floor(2)
    end

    private

    def report_path
      REPORTS.keys.map { |name| File.join(@directory, name) }.find { |path| File.file?(path) } ||
        raise(Error, "No SimpleCov report (#{REPORTS.keys.join(' or ')}) found in '#{@directory}'. " \
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
end
