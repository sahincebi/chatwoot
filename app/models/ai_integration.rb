class AiIntegration < ApplicationRecord
  belongs_to :account

  validates :provider, presence: true

  encrypts :refresh_token if Chatwoot.encryption_configured?
  encrypts :access_token if Chatwoot.encryption_configured?
end
