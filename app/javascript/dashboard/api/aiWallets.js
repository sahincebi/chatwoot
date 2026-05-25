/* global axios */
import ApiClient from './ApiClient';

class AiWalletsAPI extends ApiClient {
  constructor() {
    super('ai_wallet', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  topup(payload) {
    return axios.post(`${this.url}/topup`, payload);
  }

  paytrCheckout(payload) {
    return axios.post(`${this.url}/paytr_checkout`, payload);
  }

  getTransactions(params = {}) {
    return axios.get(`${this.url}/transactions`, { params });
  }

  getUsageLogs(params = {}) {
    return axios.get(`${this.url}/usage_logs`, { params });
  }
}

export default new AiWalletsAPI();
