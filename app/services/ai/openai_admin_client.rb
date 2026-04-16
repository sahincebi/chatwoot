class Ai::OpenaiAdminClient < Ai::OpenaiAdminBaseClient
  API_ENDPOINT = 'https://api.openai.com/v1/organization/projects'.freeze

  def create_project(name:)
    uri = URI(API_ENDPOINT)
    request = Net::HTTP::Post.new(uri.request_uri)
    request.body = { name: name }.to_json
    perform_request(request, uri)
  end
end
