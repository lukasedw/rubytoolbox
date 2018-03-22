# frozen_string_literal: true

class GithubClient
  class InvalidResponse < StandardError; end
  class UnknownRepoError < StandardError; end

  REPOSITORY_QUERY_TEMPLATE = Tilt.new(Rails.root.join("app", "graphql-queries", "github", "repo.erb"))

  attr_accessor :token, :http_client
  private :token=, :http_client=

  # Acquire token via https://developer.github.com/v4/guides/forming-calls/#authenticating-with-graphql
  # and https://github.com/settings/tokens
  #
  # No OAuth scopes are needed at all.
  def initialize(token: ENV["GITHUB_TOKEN"])
    self.token = token
    self.http_client = HTTP
                       .timeout(connect: 3, write: 3, read: 3)
  end

  def fetch_repository(path)
    owner, name = real_path(path).split("/")
    query = REPOSITORY_QUERY_TEMPLATE.render(OpenStruct.new(owner: owner, name: name))
    response = authenticated_client.post("https://api.github.com/graphql", body: { query: query }.to_json)
    handle_response response
  end

  private

  # Unfortunate hack for a limitation in github's graphql API.
  # See https://github.com/rubytoolbox/rubytoolbox/pull/94#issuecomment-372489342
  # and https://platform.github.community/t/repository-redirects-in-api-v4-graphql/4417
  def real_path(path)
    response = http_client.head File.join("https://github.com", path)
    case response.status
    when 200
      path
    when 301, 302
      Github.detect_repo_name response.headers["Location"]
    else
      raise UnknownRepoError, "Cannot find repo #{path} on github :("
    end
  end

  def handle_response(response)
    parsed_body = Oj.load(response.body)
    raise InvalidResponse, parsed_body["errors"].map { |e| e["message"] }.join(", ") if parsed_body["errors"]
    RepositoryData.new parsed_body
  end

  def authenticated_client
    @authenticated_client ||= http_client.headers(
      authorization: "bearer #{token}",
      "User-Agent" => HttpService::USER_AGENT
    )
  end
end
