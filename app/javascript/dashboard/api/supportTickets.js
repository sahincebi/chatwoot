/* global axios */
import ApiClient from './ApiClient';

class SupportTicketsAPI extends ApiClient {
  constructor() {
    super('support_tickets', { accountScoped: true });
  }

  create(payload) {
    return axios.post(this.url, payload, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  list() {
    return axios.get(this.url);
  }

  show(ticketId) {
    return axios.get(`${this.url}/${ticketId}`);
  }

  createMessage(ticketId, payload) {
    return axios.post(`${this.url}/${ticketId}/messages`, payload, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new SupportTicketsAPI();
