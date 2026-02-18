class Instagram::BaseSendService < Base::SendOnChannelService
  pattr_initialize [:message!]

  private

  delegate :additional_attributes, to: :contact

  def perform_reply
    send_attachments if message.attachments.present?
    send_content if message.content.present?
  rescue StandardError => e
    handle_error(e)
  end

  def send_attachments
    message.attachments.each do |attachment|
      send_message(attachment_message_params(attachment))
    end
  end

  def send_content
    send_message(message_params)
  end

  def handle_error(error)
    ChatwootExceptionTracker.new(error, account: message.account, user: message.sender).capture_exception
  end

  def message_params
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        text: message.outgoing_content
      }
    }

    merge_human_agent_tag(params)
  end

  def attachment_message_params(attachment)
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        attachment: {
          type: attachment_type(attachment),
          payload: {
            url: attachment.download_url
          }
        }
      }
    }

    merge_human_agent_tag(params)
  end

  def process_response(response, message_content)
    parsed_response = response.parsed_response
    if response.success? && parsed_response['error'].blank?
      message.update!(source_id: parsed_response['message_id'])
      parsed_response
    else
      if retry_without_human_agent_tag?(parsed_response, message_content)
        Rails.logger.warn("Instagram response: #{external_error(parsed_response)} : retrying without HUMAN_AGENT tag")
        return send_message(without_human_agent_tag(message_content))
      end

      external_error = external_error(parsed_response)
      Rails.logger.error("Instagram response: #{external_error} : #{message_content}")
      Messages::StatusUpdateService.new(message, 'failed', external_error).perform
      nil
    end
  end

  def external_error(response)
    error_message = response.dig('error', 'message')
    error_code = response.dig('error', 'code')

    # https://developers.facebook.com/docs/messenger-platform/error-codes
    # Access token has expired or become invalid. This may be due to a password change,
    # removal of the connected app from Instagram account settings, or other reasons.
    channel.authorization_error! if error_code == 190

    "#{error_code} - #{error_message}"
  end

  def attachment_type(attachment)
    return attachment.file_type if %w[image audio video file].include? attachment.file_type

    'file'
  end

  def retry_without_human_agent_tag?(parsed_response, message_content)
    human_agent_tag_payload?(message_content) && human_agent_not_approved_error?(parsed_response)
  end

  def human_agent_tag_payload?(message_content)
    tag = message_content[:tag] || message_content['tag']
    messaging_type = message_content[:messaging_type] || message_content['messaging_type']

    tag.to_s.casecmp('HUMAN_AGENT').zero? && messaging_type.to_s.casecmp('MESSAGE_TAG').zero?
  end

  def human_agent_not_approved_error?(parsed_response)
    error_code = parsed_response.dig('error', 'code').to_i
    error_message = parsed_response.dig('error', 'message').to_s.downcase

    error_code == 10 && error_message.include?('human agent') && error_message.include?('review')
  end

  def without_human_agent_tag(message_content)
    payload = message_content.deep_dup
    payload.delete(:messaging_type)
    payload.delete('messaging_type')
    payload.delete(:tag)
    payload.delete('tag')
    payload
  end

  # Methods to be implemented by child classes
  def send_message(message_content)
    raise NotImplementedError, 'Subclasses must implement send_message'
  end

  def merge_human_agent_tag(params)
    raise NotImplementedError, 'Subclasses must implement merge_human_agent_tag'
  end
end
