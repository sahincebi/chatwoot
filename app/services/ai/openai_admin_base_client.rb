require 'net/http'
require 'json'
require 'uri'

class Ai::OpenaiAdminBaseClient
  class Error < StandardError; end
  class MissingKeyError < StandardError; end

  def initialize
    @api_key = ENV['OPENAI_ADMIN_API_KEY']
    raise MissingKeyError, 'OPENAI_ADMIN_API_KEY is not set' if @api_key.blank?
  end

  private

  def perform_request(request, uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "OpenAI admin API error (status=#{response.code}): #{response.body}"
    end

    JSON.parse(response.body)
  end
end
