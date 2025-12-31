require 'rails_helper'

RSpec.describe Account, type: :model do
  self.use_transactional_tests = false if respond_to?(:use_transactional_tests=)
  self.use_transactional_fixtures = false if respond_to?(:use_transactional_fixtures=)

  it 'auto-creates ai_wallet after account create' do
    account = create(:account, name: 'Wallet Test')

    wallet = AiWallet.find_by(account_id: account.id)

    expect(wallet).to be_present
    expect(wallet.currency).to eq('USD')
    expect(wallet.balance_cents).to eq(0)
  ensure
    account&.destroy!
  end
end
