# frozen_string_literal: true

module SimplecovGate
  # The combined verdict over every criterion the gate enforced: it
  # passes only if each one does, and reads as one sentence per
  # criterion.
  Verdict = Struct.new(:results) do
    def passed?
      results.all?(&:passed?)
    end

    def message
      results.map(&:message).join("; ")
    end

    def conclusion
      passed? ? "success" : "failure"
    end
  end
end
