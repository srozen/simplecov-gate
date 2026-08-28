# frozen_string_literal: true

module SimplecovGate
  # The verdict of comparing one criterion's coverage percentage against
  # its minimum, and the single source of its human-readable message.
  Result = Struct.new(:criterion, :percent, :minimum) do
    def passed?
      percent >= minimum
    end

    def message
      format("%s coverage %.2f%% %s the minimum %.2f%%",
             criterion.label, percent, passed? ? "meets" : "is below", minimum)
    end
  end
end
