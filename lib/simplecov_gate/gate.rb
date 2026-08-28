# frozen_string_literal: true

module SimplecovGate
  # Facade tying the pieces together: reads the SimpleCov report once and
  # compares each criterion's coverage against its minimum.
  class Gate
    def initialize(minimums:, coverage_path:)
      @minimums = minimums
      @coverage_path = coverage_path
    end

    def check
      report = Report.new(@coverage_path)
      Verdict.new(@minimums.map { |criterion, minimum| Result.new(criterion, report.percent(criterion), minimum) })
    end
  end
end
