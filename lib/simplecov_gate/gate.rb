# frozen_string_literal: true

module SimplecovGate
  # Facade tying the pieces together: reads the SimpleCov report and
  # compares its total line coverage against the minimum.
  class Gate
    def initialize(minimum:, coverage_path:)
      @minimum = minimum
      @coverage_path = coverage_path
    end

    def check
      Result.new(Report.new(@coverage_path).percent, @minimum)
    end
  end
end
