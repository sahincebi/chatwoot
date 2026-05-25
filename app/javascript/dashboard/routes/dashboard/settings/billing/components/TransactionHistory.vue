<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AiWalletsAPI from 'dashboard/api/aiWallets';

const { t, locale } = useI18n();

const transactions = ref([]);
const isLoading = ref(true);
const currentPage = ref(1);
const totalPages = ref(1);
const totalCount = ref(0);
const kindFilter = ref('');

const KIND_BADGE = {
  topup: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/50 dark:text-emerald-200',
  debit: 'bg-rose-100 text-rose-800 dark:bg-rose-900/50 dark:text-rose-200',
  refund: 'bg-sky-100 text-sky-800 dark:bg-sky-900/50 dark:text-sky-200',
  adjustment: 'bg-n-slate-3 text-n-slate-12',
};

const KINDS = ['topup', 'debit', 'refund', 'adjustment'];

const formatAmount = transaction => {
  const currency = (transaction.currency || 'USD').toUpperCase();
  const amount = (transaction.amount_cents || 0) / 100;
  const sign = transaction.kind === 'debit' ? '-' : '+';
  return `${sign}${new Intl.NumberFormat(locale.value || 'en-US', {
    style: 'currency',
    currency,
  }).format(amount)}`;
};

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

const describeTransaction = transaction => {
  if (transaction.note) return transaction.note;
  if (transaction.provider_ref) return `${transaction.provider || ''} · ${transaction.provider_ref}`.trim();
  return transaction.provider || '—';
};

const loadTransactions = async () => {
  isLoading.value = true;
  try {
    const params = { page: currentPage.value };
    if (kindFilter.value) params.kind = kindFilter.value;
    const { data } = await AiWalletsAPI.getTransactions(params);
    transactions.value = data.data || [];
    totalPages.value = data.meta?.total_pages || 1;
    totalCount.value = data.meta?.total_count || 0;
  } catch (error) {
    useAlert(t('BILLING.TRANSACTIONS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const goToPage = page => {
  if (page < 1 || page > totalPages.value) return;
  currentPage.value = page;
  loadTransactions();
};

const applyKindFilter = kind => {
  kindFilter.value = kindFilter.value === kind ? '' : kind;
  currentPage.value = 1;
  loadTransactions();
};

const hasTransactions = computed(() => transactions.value.length > 0);

onMounted(loadTransactions);
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-sm text-n-slate-11">{{ $t('BILLING.TRANSACTIONS.FILTER_LABEL') }}</span>
      <button
        v-for="kind in KINDS"
        :key="kind"
        type="button"
        :class="[
          'inline-flex items-center rounded-full px-3 py-1 text-xs font-medium border transition-colors',
          kindFilter === kind
            ? 'bg-n-solid-active border-n-strong text-n-slate-12'
            : 'bg-n-solid-2 border-n-weak text-n-slate-11 hover:bg-n-solid-3',
        ]"
        @click="applyKindFilter(kind)"
      >
        {{ $t(`BILLING.TRANSACTIONS.KIND.${kind.toUpperCase()}`) }}
      </button>
    </div>

    <div class="rounded-xl border border-n-weak bg-n-solid-2 overflow-hidden">
      <div v-if="isLoading" class="px-6 py-10 flex justify-center">
        <Spinner />
      </div>
      <div
        v-else-if="!hasTransactions"
        class="px-6 py-10 text-center text-sm text-n-slate-11"
      >
        {{ $t('BILLING.TRANSACTIONS.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-xs uppercase text-n-slate-11 bg-n-solid-3">
            <th class="px-4 py-3 font-medium">{{ $t('BILLING.TRANSACTIONS.COLUMNS.DATE') }}</th>
            <th class="px-4 py-3 font-medium">{{ $t('BILLING.TRANSACTIONS.COLUMNS.KIND') }}</th>
            <th class="px-4 py-3 font-medium text-right">{{ $t('BILLING.TRANSACTIONS.COLUMNS.AMOUNT') }}</th>
            <th class="px-4 py-3 font-medium">{{ $t('BILLING.TRANSACTIONS.COLUMNS.DESCRIPTION') }}</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr v-for="tx in transactions" :key="tx.id" class="hover:bg-n-solid-3">
            <td class="px-4 py-3 text-n-slate-12 whitespace-nowrap">{{ formatDate(tx.created_at) }}</td>
            <td class="px-4 py-3">
              <span
                :class="[
                  'inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium',
                  KIND_BADGE[tx.kind] || KIND_BADGE.adjustment,
                ]"
              >
                {{ $t(`BILLING.TRANSACTIONS.KIND.${(tx.kind || '').toUpperCase()}`) }}
              </span>
            </td>
            <td class="px-4 py-3 text-right font-medium text-n-slate-12 whitespace-nowrap">
              {{ formatAmount(tx) }}
            </td>
            <td class="px-4 py-3 text-n-slate-11">{{ describeTransaction(tx) }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <div
      v-if="hasTransactions && totalPages > 1"
      class="flex items-center justify-between text-sm text-n-slate-11"
    >
      <span>
        {{ $t('BILLING.TRANSACTIONS.PAGINATION', { current: currentPage, total: totalPages, count: totalCount }) }}
      </span>
      <div class="flex gap-2">
        <Button
          variant="outline"
          color="slate"
          size="sm"
          :label="$t('BILLING.TRANSACTIONS.PREV')"
          :disabled="currentPage <= 1"
          @click="goToPage(currentPage - 1)"
        />
        <Button
          variant="outline"
          color="slate"
          size="sm"
          :label="$t('BILLING.TRANSACTIONS.NEXT')"
          :disabled="currentPage >= totalPages"
          @click="goToPage(currentPage + 1)"
        />
      </div>
    </div>
  </div>
</template>
