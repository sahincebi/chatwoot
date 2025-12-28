import { frontendURL } from '../../../helper/URLHelper';
import SupportTicketNew from './SupportTicketNew.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/support/new'),
      name: 'support_ticket_new',
      component: SupportTicketNew,
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
    },
  ],
};
