# frozen_string_literal: true

# Loads the whole suite in one process, which is how CI runs it: the
# dogfooded 100% gate needs every file's coverage in a single report.
Dir[File.expand_path("*_test.rb", __dir__)].sort.each { |test_file| require test_file }
