# frozen_string_literal: true

# Gates a build on the coverage reported by SimpleCov.
module SimplecovGate
  Error = Class.new(StandardError)
end

require_relative "simplecov_gate/criterion"
require_relative "simplecov_gate/result"
require_relative "simplecov_gate/verdict"
require_relative "simplecov_gate/report"
require_relative "simplecov_gate/gate"
require_relative "simplecov_gate/check_run"
require_relative "simplecov_gate/reporter"
require_relative "simplecov_gate/cli"
