# frozen_string_literal: true

require "json"
require "net/http"

module SimplecovGate
  # Publishes the verdict as a dedicated check run on the pull request,
  # named after the action. Cosmetic by design: any hiccup surfaces as a
  # workflow warning and never fails the gate.
  class CheckRun
    NAME = "SimpleCov Gate"
    TOKEN = "SIMPLECOV_GATE_GITHUB_TOKEN"

    def initialize(env:, stdout:, transport: Net::HTTP.method(:post))
      @env = env
      @stdout = stdout
      @transport = transport
    end

    def publish(conclusion:, title:)
      return if token.empty? || repository.empty?

      response = @transport.call(uri, JSON.generate(payload(conclusion, title)), headers)
      return if response.code.start_with?("2")

      warn_failure("GitHub responded with #{response.code}; grant the workflow `checks: write` permission")
    rescue StandardError => e
      warn_failure(e.message)
    end

    private

    def token
      @env[TOKEN].to_s
    end

    def repository
      @env["GITHUB_REPOSITORY"].to_s
    end

    def uri
      URI("#{@env.fetch('GITHUB_API_URL', 'https://api.github.com')}/repos/#{repository}/check-runs")
    end

    def headers
      {
        "Authorization" => "Bearer #{token}",
        "Accept" => "application/vnd.github+json",
        "X-GitHub-Api-Version" => "2022-11-28",
        "Content-Type" => "application/json"
      }
    end

    def payload(conclusion, title)
      {
        name: NAME,
        head_sha: head_sha,
        status: "completed",
        conclusion: conclusion,
        output: { title: title, summary: title }
      }
    end

    # On pull_request events GITHUB_SHA points to the synthetic merge
    # commit, whose check runs would not surface on the pull request, so
    # prefer the head of the pull request from the event payload.
    def head_sha
      event.dig("pull_request", "head", "sha") || @env["GITHUB_SHA"]
    end

    def event
      path = @env["GITHUB_EVENT_PATH"].to_s
      File.file?(path) ? JSON.parse(File.read(path)) : {}
    end

    def warn_failure(reason)
      @stdout.puts "::warning::Could not create the '#{NAME}' check run: #{reason}."
    end
  end
end
