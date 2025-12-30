<script setup>
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SupportTicketsAPI from 'dashboard/api/supportTickets';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const route = useRoute();

const tickets = ref([]);
const isLoading = ref(true);

const loadTickets = async () => {
  isLoading.value = true;
  try {
    const { data } = await SupportTicketsAPI.list();
    tickets.value = data?.tickets || [];
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error(error);
    useAlert(t('SUPPORT.LIST.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const formatTimestamp = value => {
  if (!value) return '';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '' : date.toLocaleString();
};

onMounted(loadTickets);
</script>

<template>
  <div class="flex flex-col gap-6 p-6 max-w-4xl">
    <div class="flex items-center justify-between">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('SUPPORT.LIST.TITLE') }}
      </h1>
      <router-link :to="{ name: 'support_ticket_new', params: { accountId: route.params.accountId } }">
        <NextButton blue>
          {{ t('SUPPORT.LIST.NEW_TICKET') }}
        </NextButton>
      </router-link>
    </div>

    <div v-if="isLoading" class="text-sm text-n-slate-11">
      {{ t('SUPPORT.LIST.LOADING') }}
    </div>

    <div v-else>
      <div v-if="!tickets.length" class="text-sm text-n-slate-11">
        {{ t('SUPPORT.LIST.EMPTY') }}
      </div>
      <div v-else class="overflow-x-auto rounded-lg border border-n-weak">
        <table class="min-w-full text-sm">
          <thead class="bg-n-solid-2 text-n-slate-11">
            <tr class="text-left">
              <th class="py-2 px-3">{{ t('SUPPORT.LIST.SUBJECT') }}</th>
              <th class="py-2 px-3">{{ t('SUPPORT.LIST.STATUS') }}</th>
              <th class="py-2 px-3">{{ t('SUPPORT.LIST.PRIORITY') }}</th>
              <th class="py-2 px-3">{{ t('SUPPORT.LIST.LAST_ACTIVITY') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="ticket in tickets"
              :key="ticket.id"
              class="border-t border-n-weak hover:bg-n-solid-3"
            >
              <td class="py-2 px-3">
                <router-link
                  :to="{
                    name: 'support_ticket_show',
                    params: { accountId: route.params.accountId, ticketId: ticket.id },
                  }"
                  class="text-woot-500 hover:text-woot-700"
                >
                  {{ ticket.subject }}
                </router-link>
                <span
                  v-if="ticket.unread"
                  class="ml-2 inline-flex items-center rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700"
                >
                  {{ t('SUPPORT.LIST.UNREAD') }}
                </span>
              </td>
              <td class="py-2 px-3">{{ ticket.status }}</td>
              <td class="py-2 px-3">{{ ticket.priority }}</td>
              <td class="py-2 px-3">{{ formatTimestamp(ticket.last_activity_at) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
