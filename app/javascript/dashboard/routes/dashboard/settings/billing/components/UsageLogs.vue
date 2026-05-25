<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AiWalletsAPI from 'dashboard/api/aiWallets';

const { t, locale } = useI18n();
const route = useRoute();

const logs = ref([]);
const totals = ref({ total_tokens: 0, billed_cost_cents: 0 });
const totalsCurrency = ref('USD');
const isLoading = ref(true);
const currentPage = ref(1);
const totalPages = ref(1);
const totalCount = ref(0);

const today = new Date().toISOString().slice(0, 10);
const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
const fromDate = ref(thirtyDaysAgo);
const toDate = ref(today);

const accountId = computed(() => route.params.accountId);

const formatDate = value => {
  if (!value) return '';
  return new Date(value).toLocaleString(locale.value || 'en-US', {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const formatCurrency = (cents, currency = 'USD') =>
  new Intl.NumberFormat(locale.value || 'en-US', {
    style: 'currency',
    currency: (currency || 'USD').toUpperCase(),
    minimumFractionDigits: 2,
    maximumFractionDigits: 4,
  }).format((cents || 0) / 100);

const formatNumber = value =>
  new Intl.NumberFormat(locale.value || 'en-US').format(value || 0);

const conversationLink = conversationId => {
  if (!conversationId) return null;
  return `/app/accounts/${accountId.value}/conversations/${conversationId}`;
};

const loadLogs = async () => {
  isLoading.value = true;
  try {
    const params = {
      page: currentPage.value,
      from: fromDate.value,
      to: toDate.value,
    };
    const { data } = await AiWalletsAPI.getUsageLogs(params);
    logs.value = data.data || [];
    totalPages.value = data.meta?.total_pages || 1;
    totalCount.value = data.meta?.total_count || 0;
    totals.value = data.meta?.totals || { total_tokens: 0, billed_cost_cents: 0 };
    if (logs.value[0]?.currency) totalsCurrency.value = logs.value[0].currency;
  } catch (error) {
    useAlert(t('BILLING.USAGE.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const applyFilter = () => {
  currentPage.value = 1;
  loadLogs();
};

const goToPage = page => {
  if (page < 1 || page > totalPages.value) return;
  currentPage.value = page;
  loadLogs();
};

const hasLogs = computed(() => logs.value.length > 0);

onMounted(loadLogs);
</script>

<template>
  <div class="space-y-4">
    <div class="grid gap-4 md:grid-cols-2">
      <div class="rounded-xl border border-n-weak bg-n-solid-2 px-5 py-4">
        <p class="text-xs uppercase text-n-slate-11">{{ $t('BILLING.USAGE.TOTAL_TOKENS') }}</p>
        <p class="text-xl font-semibold text-n-slate-12 mt-1">{{ formatNumber(totals.total_tokens) }}</p>
      </div>
      <div class="rounded-xl border border-n-weak bg-n-solid-2 px-5 py-4">
        <p class="text-xs uppercase text-n-slate-11">{{ $t('BILLING.USAGE.TOTAL_COST') }}</p>
        <p class="text-xl font-semibold text-n-slate-12 mt-1">
          {{ formatCurrency(totals.billed_cost_cents, totalsCurrency) }}
        </p>
      </div>
    </div>

    <div class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-3 flex flex-wrap items-end gap-3">
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ $t('BILLING.USAGE.FROM') }}
        <input
          v-model="fromDate"
          type="date"
          class="mt-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm text-n-slate-12"
        />
      </label>
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ $t('BILLING.USAGE.TO') }}
        <input
          v-model="toDate"
          type="date"
          class="mt-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm text-n-slate-12"
        />
      </label>
      <Button
        :label="$t('BILLING.USAGE.APPLY')"
        color="blue"
        size="sm"
        @click="applyFilter"
      />
    </div>

    <div class="rounded-xl border border-n-weak bg-n-solid-2 overflow-hidden">
      <div v-if="isLoading" class="px-6 py-10 flex justify-center">
        <Spinner />
      </div>
      <div
        v-else-if="!hasLogs"
        class="px-6 py-10 text-center text-sm text-n-slate-11"
      >
        {{ $t('BILLING.USAGE.EMPTY') }}
      </div>
      <div v-else class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs uppercase text-n-slate-11 bg-n-solid-3">
              <th class="px-4 py-3 font-medium">{{ $t('BILLING.USAGE.COLUMNS.DATE') }}</th>
              <th class="px-4 py-3 font-medium">{{ $t('BILLING.USAGE.COLUMNS.CONVERSATION') }}</th>
              <th class="px-4 py-3 font-medium">{{ $t('BILLING.USAGE.COLUMNS.MODEL') }}</th>
              <th class="px-4 py-3 font-medium text-right">{{ $t('BILLING.USAGE.COLUMNS.INPUT') }}</th>
              <th class="px-4 py-3 font-medium text-right">{{ $t('BILLING.USAGE.COLUMNS.OUTPUT') }}</th>
              <th class="px-4 py-3 font-medium text-right">{{ $t('BILLING.USAGE.COLUMNS.TOTAL') }}</th>
              <th class="px-4 py-3 font-medium text-right">{{ $t('BILLING.USAGE.COLUMNS.COST') }}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr v-for="log in logs" :key="log.id" class="hover:bg-n-solid-3">
              <td class="px-4 py-3 text-n-slate-12 whitespace-nowrap">{{ formatDate(log.created_at) }}</td>
              <td class="px-4 py-3 text-n-slate-11">
                <router-link
                  v-if="conversationLink(log.conversation_id)"
                  :to="conversationLink(log.conversation_id)"
                  class="text-n-brand hover:underline"
                >
                  #{{ log.conversation_id }}
                </router-link>
                <span v-else>—</span>
              </td>
              <td class="px-4 py-3 text-n-slate-11">{{ log.model || '—' }}</td>
              <td class="px-4 py-3 text-right text-n-slate-11 whitespace-nowrap">{{ formatNumber(log.input_tokens) }}</td>
              <td class="px-4 py-3 text-right text-n-slate-11 whitespace-nowrap">{{ formatNumber(log.output_tokens) }}</td>
              <td class="px-4 py-3 text-right text-n-slate-12 font-medium whitespace-nowrap">{{ formatNumber(log.total_tokens) }}</td>
              <td class="px-4 py-3 text-right text-n-slate-12 font-medium whitespace-nowrap">
                {{ formatCurrency(log.billed_cost_cents, log.currency) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div
      v-if="hasLogs && totalPages > 1"
      class="flex items-center justify-between text-sm text-n-slate-11"
    >
      <span>
        {{ $t('BILLING.USAGE.PAGINATION', { current: currentPage, total: totalPages, count: totalCount }) }}
      </span>
      <div class="flex gap-2">
        <Button
          variant="outline"
          color="slate"
          size="sm"
          :label="$t('BILLING.USAGE.PREV')"
          :disabled="currentPage <= 1"
          @click="goToPage(currentPage - 1)"
        />
        <Button
          variant="outline"
          color="slate"
          size="sm"
          :label="$t('BILLING.USAGE.NEXT')"
          :disabled="currentPage >= totalPages"
          @click="goToPage(currentPage + 1)"
        />
      </div>
    </div>
  </div>
</template>
