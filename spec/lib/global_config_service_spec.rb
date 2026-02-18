require 'rails_helper'

describe GlobalConfigService do
  describe '.load' do
    before do
      GlobalConfig.clear_cache
      InstallationConfig.unscoped.where(name: 'ENABLE_ACCOUNT_SIGNUP').delete_all
    end

    it 'returns persisted false value without treating it as absent' do
      InstallationConfig.set_value('ENABLE_ACCOUNT_SIGNUP', false, locked: false)

      with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true' do
        value = described_class.load('ENABLE_ACCOUNT_SIGNUP', 'true')
        expect(value).to eq(false)
      end
    end

    it 'backfills nil installation config value from env' do
      InstallationConfig.unscoped.create!(name: 'ENABLE_ACCOUNT_SIGNUP', locked: false, serialized_value: {})

      with_modified_env ENABLE_ACCOUNT_SIGNUP: 'false' do
        value = described_class.load('ENABLE_ACCOUNT_SIGNUP', 'true')
        expect(value).to eq('false')
        expect(InstallationConfig.unscoped.find_by(name: 'ENABLE_ACCOUNT_SIGNUP')&.value).to eq('false')
      end
    end

    it 'keeps DB value when present even if env is different' do
      InstallationConfig.set_value('ENABLE_ACCOUNT_SIGNUP', 'true', locked: false)

      with_modified_env ENABLE_ACCOUNT_SIGNUP: 'false' do
        value = described_class.load('ENABLE_ACCOUNT_SIGNUP', 'false')
        expect(value).to eq('true')
      end
    end
  end
end
