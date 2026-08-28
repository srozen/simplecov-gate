# frozen_string_literal: true

module SimplecovGate
  # A SimpleCov coverage criterion the gate can enforce, and the single
  # place mapping it onto the action's input, the environment variable
  # action.yml passes it through, and the keys each report format
  # records its percentage under.
  Criterion = Struct.new(:name, :input, :total_key, :last_run_keys) do
    def env
      "SIMPLECOV_GATE_#{input.upcase.tr('-', '_')}"
    end

    # The `meta` flag recording whether SimpleCov tracked this criterion
    # at all, written to coverage.json since schema 1.0.
    def meta_flag
      "#{name}_coverage"
    end

    def label
      name.capitalize
    end
  end

  # Line coverage keeps the unqualified input name the action shipped
  # with. `.last_run.json` gained per-criterion keys in SimpleCov 0.18;
  # `covered_percent` is the line-only format that preceded them.
  Criterion::ALL = [
    Criterion.new("line", "minimum-coverage", "lines", %w[line covered_percent]),
    Criterion.new("branch", "minimum-branch-coverage", "branches", %w[branch]),
    Criterion.new("method", "minimum-method-coverage", "methods", %w[method])
  ].freeze
end
