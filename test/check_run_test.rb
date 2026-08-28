# frozen_string_literal: true

require_relative "test_helper"

# The dedicated "SimpleCov Gate" check run: what the verdict publishes,
# and how the GitHub call itself behaves when it cannot go through.
class CheckRunTest < GateTest
  def test_publishes_the_verdict
    check_run = RecordingCheckRun.new
    run_gate(files: { "coverage.json" => coverage_json(100) }, minimum: "90", check_run: check_run)

    assert_equal [{ conclusion: "success", title: "Line coverage 100.00% meets the minimum 90.00%" }],
                 check_run.published
  end

  def test_publishes_a_failure_below_the_minimum
    check_run = RecordingCheckRun.new
    run_gate(files: { "coverage.json" => coverage_json(50) }, minimum: "90", check_run: check_run)

    assert_equal [{ conclusion: "failure", title: "Line coverage 50.00% is below the minimum 90.00%" }],
                 check_run.published
  end

  def test_publishes_one_check_run_covering_every_criterion
    check_run = RecordingCheckRun.new
    files = { "coverage.json" => coverage_json(100, branch: 50.0) }
    run_gate(files: files, minimum: "90", branch_minimum: "80", check_run: check_run)

    assert_equal [{ conclusion: "failure",
                    title: "Line coverage 100.00% meets the minimum 90.00%; " \
                           "Branch coverage 50.00% is below the minimum 80.00%" }],
                 check_run.published
  end

  def test_publishes_a_failure_on_errors
    check_run = RecordingCheckRun.new
    run_gate(minimum: "90", check_run: check_run)

    assert_equal 1, check_run.published.size
    assert_equal "failure", check_run.published.first[:conclusion]
    assert_includes check_run.published.first[:title], "No SimpleCov report"
  end

  def test_posts_the_verdict_to_github
    requests = []
    stdout = StringIO.new
    check_run = github_check_run(stdout: stdout, transport: lambda { |uri, body, headers|
      requests << [uri.to_s, JSON.parse(body), headers]
      FakeResponse.new("201")
    })

    check_run.publish(conclusion: "success", title: "all good")

    uri, body, headers = requests.fetch(0)
    assert_equal "https://api.github.com/repos/acme/widgets/check-runs", uri
    assert_equal "SimpleCov Gate", body["name"]
    assert_equal "deadbeef", body["head_sha"]
    assert_equal "completed", body["status"]
    assert_equal "success", body["conclusion"]
    assert_equal "all good", body.dig("output", "title")
    assert_equal "Bearer s3cret", headers["Authorization"]
    assert_empty stdout.string
  end

  def test_prefers_the_pull_request_head_sha
    Dir.mktmpdir do |dir|
      event_path = File.join(dir, "event.json")
      File.write(event_path, %({"pull_request":{"head":{"sha":"cafe"}}}))
      requests = []
      check_run = github_check_run(env: { "GITHUB_EVENT_PATH" => event_path },
                                   transport: ->(_uri, body, _headers) { requests << JSON.parse(body); FakeResponse.new("201") })

      check_run.publish(conclusion: "success", title: "all good")

      assert_equal "cafe", requests.fetch(0).fetch("head_sha")
    end
  end

  def test_warns_when_github_declines
    stdout = StringIO.new
    check_run = github_check_run(stdout: stdout, transport: ->(*) { FakeResponse.new("403") })

    check_run.publish(conclusion: "success", title: "all good")

    assert_includes stdout.string, "::warning::Could not create the 'SimpleCov Gate' check run"
    assert_includes stdout.string, "checks: write"
  end

  def test_warns_instead_of_raising
    stdout = StringIO.new
    check_run = github_check_run(stdout: stdout, transport: ->(*) { raise "connection reset" })

    check_run.publish(conclusion: "success", title: "all good")

    assert_includes stdout.string, "connection reset"
  end

  def test_skips_quietly_without_a_token
    stdout = StringIO.new
    check_run = SimplecovGate::CheckRun.new(env: {}, stdout: stdout,
                                            transport: ->(*) { flunk "must not call GitHub" })

    check_run.publish(conclusion: "success", title: "all good")

    assert_empty stdout.string
  end

  private

  FakeResponse = Struct.new(:code)

  # Stands in for the real check run so a gate run can be asked what it
  # would have published, without reaching GitHub.
  class RecordingCheckRun
    attr_reader :published

    def initialize
      @published = []
    end

    def publish(**verdict)
      published << verdict
    end
  end

  def github_check_run(transport:, stdout: StringIO.new, env: {})
    full_env = {
      "SIMPLECOV_GATE_GITHUB_TOKEN" => "s3cret",
      "GITHUB_REPOSITORY" => "acme/widgets",
      "GITHUB_SHA" => "deadbeef"
    }.merge(env)
    SimplecovGate::CheckRun.new(env: full_env, stdout: stdout, transport: transport)
  end
end
