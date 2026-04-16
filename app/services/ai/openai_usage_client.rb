class Ai::OpenaiUsageClient < Ai::OpenaiAdminBaseClient
  API_ENDPOINT = 'https://api.openai.com/v1/organization/usage/completions'.freeze

  def completions_usage(start_time:, end_time:, project_id: nil)
    uri = URI(API_ENDPOINT)
    params = {
      'start_time' => start_time,
      'end_time' => end_time,
      'bucket_width' => '1d'
    }
    params['project_ids[]'] = project_id if project_id.present?
    uri.query = URI.encode_www_form(params)

    request = Net::HTTP::Get.new(uri.request_uri)
    perform_request(request, uri)
  end
end
