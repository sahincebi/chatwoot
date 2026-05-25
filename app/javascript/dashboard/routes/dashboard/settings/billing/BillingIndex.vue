<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import BillingCard from './components/BillingCard.vue';
import LowBalanceBanner from './components/LowBalanceBanner.vue';
import TransactionHistory from './components/TransactionHistory.vue';
import UsageLogs from './components/UsageLogs.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import Modal from 'dashboard/components/Modal.vue';
import AiWalletsAPI from 'dashboard/api/aiWallets';

const { t } = useI18n();
const isLoading = ref(true);
const isSubmitting = ref(false);
const showTopupModal = ref(false);
const amountUsd = ref('');
const note = ref('');
const wallet = ref({
  balance_cents: 0,
  currency: 'USD',
  status: 'active',
  low_balance: false,
  low_balance_threshold_cents: 500,
});

const TABS = ['overview', 'transactions', 'usage'];
const activeTab = ref('overview');

const formattedBalance = computed(() => {
  const currency = wallet.value.currency || 'USD';
  const amount = (wallet.value.balance_cents || 0) / 100;
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency.toUpperCase(),
  }).format(amount);
});

const loadWallet = async () => {
  isLoading.value = true;
  try {
    const { data } = await AiWalletsAPI.show();
    wallet.value = { ...wallet.value, ...data };
  } catch (error) {
    useAlert(t('BILLING.TOPUP.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const openTopupModal = () => {
  showTopupModal.value = true;
};

const closeTopupModal = () => {
  showTopupModal.value = false;
};

const parseAmountCents = () => {
  const normalized = amountUsd.value.replace(',', '.');
  const parsed = Number.parseFloat(normalized);
  if (Number.isNaN(parsed) || parsed <= 0) return null;
  return Math.round(parsed * 100);
};

const submitTopup = async () => {
  const amountCents = parseAmountCents();
  if (!amountCents) {
    useAlert(t('BILLING.TOPUP.INVALID_AMOUNT'));
    return;
  }

  isSubmitting.value = true;
  try {
    const payload = {
      amount_cents: amountCents,
    };
    if (note.value) payload.note = note.value;
    const { data } = await AiWalletsAPI.paytrCheckout(payload);
    if (!data?.checkout_url) {
      throw new Error('checkout_url_missing');
    }

    window.open(data.checkout_url, '_blank', 'noopener,noreferrer');
    useAlert(t('BILLING.TOPUP.CHECKOUT_STARTED'));
    amountUsd.value = '';
    note.value = '';
    closeTopupModal();
  } catch (error) {
    useAlert(t('BILLING.TOPUP.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};

onMounted(loadWallet);
</script>

<template>
  <div class="flex-1 w-full">
    <BaseSettingsHeader
      :title="$t('BILLING.TITLE')"
      :description="$t('BILLING.DESCRIPTION')"
    />

    <LowBalanceBanner
      v-if="!isLoading && wallet.low_balance"
      class="mt-6"
      :balance-cents="wallet.balance_cents"
      :threshold-cents="wallet.low_balance_threshold_cents"
      :currency="wallet.currency"
      @add-credit="openTopupModal"
    />

    <div class="mt-6">
      <div class="flex gap-1 border-b border-n-weak">
        <button
          v-for="tab in TABS"
          :key="tab"
          type="button"
          :class="[
            'px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors',
            activeTab === tab
              ? 'border-n-brand text-n-slate-12'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12',
          ]"
          @click="activeTab = tab"
        >
          {{ $t(`BILLING.TABS.${tab.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <div v-show="activeTab === 'overview'" class="mt-6 space-y-6">
      <div
        class="rounded-xl border border-n-weak bg-n-solid-2 px-6 py-5 flex items-center justify-between"
      >
        <div>
          <p class="text-sm text-n-slate-11">
            {{ $t('BILLING.CREDIT_BALANCE') }}
          </p>
          <p class="text-2xl font-semibold text-n-slate-12">
            {{ isLoading ? $t('BILLING.LOADING') : formattedBalance }}
          </p>
        </div>
        <Button
          :label="$t('BILLING.ADD_CREDIT')"
          color="blue"
          @click="openTopupModal"
        />
      </div>

      <div class="grid gap-4 md:grid-cols-2">
        <BillingCard
          :title="$t('BILLING.PAYMENT_METHODS')"
          :description="$t('BILLING.COMING_SOON')"
        >
          <div class="px-5 text-sm text-n-slate-11">
            {{ $t('BILLING.COMING_SOON') }}
          </div>
        </BillingCard>
        <BillingCard
          :title="$t('BILLING.PRICING')"
          :description="$t('BILLING.COMING_SOON')"
        >
          <div class="px-5 text-sm text-n-slate-11">
            {{ $t('BILLING.COMING_SOON') }}
          </div>
        </BillingCard>
      </div>
    </div>

    <div v-if="activeTab === 'transactions'" class="mt-6">
      <TransactionHistory />
    </div>

    <div v-if="activeTab === 'usage'" class="mt-6">
      <UsageLogs />
    </div>

    <Modal v-model:show="showTopupModal" @close="closeTopupModal">
      <div class="modal-content">
        <h3 class="text-lg font-semibold text-n-slate-12">
          {{ $t('BILLING.TOPUP.TITLE') }}
        </h3>
        <div class="mt-4 space-y-4">
          <NextInput
            v-model="amountUsd"
            name="amount"
            :label="$t('BILLING.TOPUP.AMOUNT')"
            :placeholder="$t('BILLING.TOPUP.AMOUNT_PLACEHOLDER')"
          />
          <NextInput
            v-model="note"
            name="note"
            :label="$t('BILLING.TOPUP.NOTE')"
            :placeholder="$t('BILLING.TOPUP.NOTE_PLACEHOLDER')"
          />
        </div>
        <div class="mt-6 flex justify-end gap-2">
          <Button
            :label="$t('BILLING.TOPUP.CANCEL')"
            slate
            @click="closeTopupModal"
          />
          <Button
            :label="$t('BILLING.TOPUP.SUBMIT')"
            color="blue"
            :is-loading="isSubmitting"
            @click="submitTopup"
          />
        </div>
      </div>
    </Modal>
  </div>
</template>
