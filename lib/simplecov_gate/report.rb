# frozen_string_literal: true

require "json"

module SimplecovGate
  # Extracts a criterion's total coverage from a SimpleCov report.
  #
  # Reads coverage.json, written by default since SimpleCov 1.0, and falls
  # back to .last_run.json for older versions. The file is read once and
  # queried per criterion. Percentages are floored to two decimals,
  # mirroring SimpleCov's own strictness.
  class Report
    REPORTS = {
      "coverage.json" => ->(data, criterion) { data.dig("total", criterion.total_key, "percent") },
      ".last_run.json" => lambda { |data, criterion|
        criterion.last_run_keys.map { |key| data.dig("result", key) }.compact.first
      }
    }.freeze

    def initialize(directory)
      @directory = directory
    end

    def percent(criterion)
      percent = extract(criterion)
      raise Error, missing_message(criterion) unless percent.is_a?(Numeric)

      percent.to_f.floor(2)
    end

    private

    def extract(criterion)
      REPORTS.fetch(File.basename(path)).call(data, criterion)
    rescue TypeError
      nil
    end

    # SimpleCov only records a criterion it was asked to track, so an
    # absent percentage is far more often a configuration gap than a
    # malformed report — say which when the report tells us.
    def missing_message(criterion)
      unless untracked?(criterion)
        return "#{path} does not contain a total #{criterion.name} coverage percentage; " \
               "is it a SimpleCov report?"
      end

      "#{path} reports no #{criterion.name} coverage: SimpleCov did not track it in this run. " \
        "Add `enable_coverage :#{criterion.name}` to your SimpleCov configuration, " \
        "or drop the '#{criterion.input}' input."
    end

    def untracked?(criterion)
      meta = data["meta"]
      meta.is_a?(Hash) && meta[criterion.meta_flag] == false
    end

    def path
      @path ||= locate
    end

    def locate
      REPORTS.keys.map { |name| File.join(@directory, name) }.find { |candidate| File.file?(candidate) } ||
        raise(Error, "No SimpleCov report (#{REPORTS.keys.join(' or ')}) found in '#{@directory}'. " \
                     "Run the tests with SimpleCov enabled before this action, or point " \
                     "'coverage-path' at SimpleCov's coverage directory.")
    end

    def data
      @data ||= parse(path)
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
