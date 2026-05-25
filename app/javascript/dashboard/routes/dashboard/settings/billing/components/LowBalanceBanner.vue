<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  balanceCents: {
    type: Number,
    required: true,
  },
  thresholdCents: {
    type: Number,
    required: true,
  },
  currency: {
    type: String,
    default: 'USD',
  },
});

const emit = defineEmits(['add-credit']);

const formattedThreshold = computed(() =>
  new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: (props.currency || 'USD').toUpperCase(),
  }).format(props.thresholdCents / 100)
);
</script>

<template>
  <div
    class="rounded-xl border border-amber-300 bg-amber-50 dark:bg-amber-950/40 dark:border-amber-700 px-4 py-3 flex items-center gap-3"
  >
    <Icon
      icon="i-lucide-triangle-alert"
      class="text-amber-600 dark:text-amber-400 size-5 shrink-0"
    />
    <div class="flex-1 text-sm text-amber-900 dark:text-amber-200">
      {{ $t('BILLING.LOW_BALANCE.MESSAGE', { threshold: formattedThreshold }) }}
    </div>
    <Button
      :label="$t('BILLING.ADD_CREDIT')"
      size="sm"
      color="amber"
      @click="emit('add-credit')"
    />
  </div>
</template>
