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
}

export default new AiWalletsAPI();
