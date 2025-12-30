import { frontendURL } from '../../../helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from '../../../constants/permissions';
import SupportTicketIndex from './SupportTicketIndex.vue';
import SupportTicketNew from './SupportTicketNew.vue';
import SupportTicketShow from './SupportTicketShow.vue';

const SUPPORT_PERMISSIONS = [...ROLES, ...CONVERSATION_PERMISSIONS];

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/support/tickets'),
      name: 'support_ticket_index',
      component: SupportTicketIndex,
      meta: {
        permissions: SUPPORT_PERMISSIONS,
      },
    },
    {
      path: frontendURL('accounts/:accountId/support/new'),
      name: 'support_ticket_new',
      component: SupportTicketNew,
      meta: {
        permissions: SUPPORT_PERMISSIONS,
      },
    },
    {
      path: frontendURL('accounts/:accountId/support/tickets/:ticketId'),
      name: 'support_ticket_show',
      component: SupportTicketShow,
      meta: {
        permissions: SUPPORT_PERMISSIONS,
      },
    },
  ],
};
