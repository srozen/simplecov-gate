# frozen_string_literal: true

module SimplecovGate
  # The verdict of comparing a coverage percentage against a minimum,
  # and the single source of its human-readable message.
  Result = Struct.new(:percent, :minimum) do
    def passed?
      percent >= minimum
    end

    def message
      format("Line coverage %.2f%% %s the minimum %.2f%%",
             percent, passed? ? "meets" : "is below", minimum)
    end

    def conclusion
      passed? ? "success" : "failure"
    end
  end
end
