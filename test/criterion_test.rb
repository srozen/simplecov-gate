# frozen_string_literal: true

require_relative "test_helper"

# Every criterion the gate knows about has to reach the environment, and
# action.yml, under the names it declares.
class CriterionTest < GateTest
  def test_maps_each_action_input_onto_an_environment_variable
    mapping = SimplecovGate::Criterion::ALL.to_h { |criterion| [criterion.input, criterion.env] }

    assert_equal({ "minimum-coverage" => "SIMPLECOV_GATE_MINIMUM_COVERAGE",
                   "minimum-branch-coverage" => "SIMPLECOV_GATE_MINIMUM_BRANCH_COVERAGE",
                   "minimum-method-coverage" => "SIMPLECOV_GATE_MINIMUM_METHOD_COVERAGE" }, mapping)
  end

  def test_the_action_manifest_declares_every_criterion_input
    manifest = File.read(File.expand_path("../action.yml", __dir__))

    SimplecovGate::Criterion::ALL.each do |criterion|
      assert_includes manifest, "  #{criterion.input}:"
      assert_includes manifest, "#{criterion.env}: ${{ inputs.#{criterion.input} }}"
    end
  end
end
