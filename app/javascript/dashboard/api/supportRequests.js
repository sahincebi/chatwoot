import ApiClient from './ApiClient';

class SupportRequestsAPI extends ApiClient {
  constructor() {
    super('support_requests', { accountScoped: true });
  }
}

export default new SupportRequestsAPI();
