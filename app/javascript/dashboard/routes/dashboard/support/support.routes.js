import { frontendURL } from '../../../helper/URLHelper';
import SupportTicketNew from './SupportTicketNew.vue';
import SupportTicketShow from './SupportTicketShow.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/support/tickets'),
      name: 'support_ticket_index',
      redirect: to => ({
        name: 'support_ticket_new',
        params: { accountId: to.params.accountId },
      }),
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/support/new'),
      name: 'support_ticket_new',
      component: SupportTicketNew,
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/support/tickets/:ticketId'),
      name: 'support_ticket_show',
      component: SupportTicketShow,
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
    },
  ],
};
