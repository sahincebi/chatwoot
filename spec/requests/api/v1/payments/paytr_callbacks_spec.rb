require 'rails_helper'

RSpec.describe 'Api::V1::Payments::PaytrCallbacks' do
  describe 'POST /api/v1/payments/paytr/callback' do
    let(:service) { instance_double(Ai::Payments::PaytrService) }

    before do
      allow(Ai::Payments::PaytrService).to receive(:new).and_return(service)
    end

    it 'returns OK when callback is processed' do
      allow(service).to receive(:process_callback!).and_return({
        acknowledged: true,
        result: 'paid',
        merchant_oid: 'OID123'
      })

      post '/api/v1/payments/paytr/callback', params: {
        merchant_oid: 'OID123',
        status: 'success',
        total_amount: '10000',
        hash: 'fake-hash'
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('OK')
      expect(service).to have_received(:process_callback!).with(
        payload: hash_including(
          merchant_oid: 'OID123',
          status: 'success',
          total_amount: '10000',
          hash: 'fake-hash'
        )
      )
    end

    it 'returns unauthorized for invalid signature' do
      allow(service).to receive(:process_callback!).and_raise(
        Ai::Payments::PaytrService::InvalidSignatureError,
        'invalid callback signature'
      )

      post '/api/v1/payments/paytr/callback', params: {
        merchant_oid: 'OID124',
        status: 'success',
        total_amount: '10000',
        hash: 'bad-hash'
      }

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to eq('FAIL')
    end

    it 'returns unprocessable content for missing configuration' do
      allow(service).to receive(:process_callback!).and_raise(
        Ai::Payments::PaytrService::ConfigurationError,
        'Missing PayTR config'
      )

      post '/api/v1/payments/paytr/callback', params: {
        merchant_oid: 'OID125',
        status: 'success',
        total_amount: '10000',
        hash: 'fake-hash'
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to eq('FAIL')
    end

    it 'returns forbidden when callback ip is not allowlisted' do
      with_modified_env('PAYTR_CALLBACK_IP_ALLOWLIST' => '203.0.113.10') do
        allow(service).to receive(:process_callback!).and_return(
          acknowledged: true, result: 'paid', merchant_oid: 'OID126'
        )

        post '/api/v1/payments/paytr/callback', params: {
          merchant_oid: 'OID126',
          status: 'success',
          total_amount: '10000',
          hash: 'fake-hash'
        }
      end

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to eq('FAIL')
      expect(service).not_to have_received(:process_callback!)
    end
  end
end
