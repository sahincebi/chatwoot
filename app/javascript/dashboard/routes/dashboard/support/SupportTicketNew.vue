<script setup>
import { ref, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SupportTicketsAPI from 'dashboard/api/supportTickets';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const subject = ref('');
const category = ref('technical');
const priority = ref('normal');
const description = ref('');
const files = ref([]);
const isSubmitting = ref(false);

const categoryOptions = computed(() => [
  { value: 'technical', label: t('SUPPORT.NEW.CATEGORY.OPTIONS.TECHNICAL') },
  { value: 'billing', label: t('SUPPORT.NEW.CATEGORY.OPTIONS.BILLING') },
  {
    value: 'integration',
    label: t('SUPPORT.NEW.CATEGORY.OPTIONS.INTEGRATION'),
  },
  {
    value: 'feature_request',
    label: t('SUPPORT.NEW.CATEGORY.OPTIONS.FEATURE_REQUEST'),
  },
  { value: 'other', label: t('SUPPORT.NEW.CATEGORY.OPTIONS.OTHER') },
]);

const priorityOptions = computed(() => [
  { value: 'normal', label: t('SUPPORT.NEW.PRIORITY.OPTIONS.NORMAL') },
  { value: 'high', label: t('SUPPORT.NEW.PRIORITY.OPTIONS.HIGH') },
  { value: 'urgent', label: t('SUPPORT.NEW.PRIORITY.OPTIONS.URGENT') },
]);

const isFormInvalid = computed(
  () =>
    isSubmitting.value ||
    !subject.value.trim() ||
    !description.value.trim()
);

const onFilesChange = event => {
  files.value = Array.from(event.target.files || []);
};

const submitTicket = async () => {
  if (isFormInvalid.value) return;
  isSubmitting.value = true;
  try {
    const payload = new FormData();
    payload.append('subject', subject.value.trim());
    payload.append('category', category.value);
    payload.append('priority', priority.value);
    payload.append('description', description.value.trim());
    files.value.forEach(file => payload.append('attachments[]', file));

    const { data } = await SupportTicketsAPI.create(payload);
    const ticketId = data?.ticket_id || data?.id;
    if (!ticketId) {
      useAlert(t('SUPPORT.NEW.ERROR'));
      return;
    }
    useAlert(t('SUPPORT.NEW.SUCCESS_WITH_ID', { id: ticketId }));
    await router.replace({
      name: 'support_ticket_show',
      params: { accountId: route.params.accountId, ticketId },
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error(error);
    useAlert(error?.response?.data?.error || t('SUPPORT.NEW.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-6 p-6 max-w-3xl">
    <div class="flex flex-col gap-2">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('SUPPORT.NEW.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ t('SUPPORT.NEW.DESCRIPTION') }}
      </p>
    </div>

    <form class="grid gap-4" @submit.prevent="submitTicket">
      <WithLabel :label="t('SUPPORT.NEW.SUBJECT.LABEL')">
        <NextInput
          v-model="subject"
          type="text"
          class="w-full"
          :placeholder="t('SUPPORT.NEW.SUBJECT.PLACEHOLDER')"
          :disabled="isSubmitting"
        />
      </WithLabel>

      <WithLabel :label="t('SUPPORT.NEW.CATEGORY.LABEL')">
        <select
          v-model="category"
          class="!mb-0 text-sm"
          :disabled="isSubmitting"
        >
          <option
            v-for="option in categoryOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
      </WithLabel>

      <WithLabel :label="t('SUPPORT.NEW.PRIORITY.LABEL')">
        <select
          v-model="priority"
          class="!mb-0 text-sm"
          :disabled="isSubmitting"
        >
          <option
            v-for="option in priorityOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
      </WithLabel>

      <WithLabel :label="t('SUPPORT.NEW.MESSAGE.LABEL')">
        <textarea
          v-model="description"
          rows="6"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-12"
          :placeholder="t('SUPPORT.NEW.MESSAGE.PLACEHOLDER')"
          :disabled="isSubmitting"
        />
      </WithLabel>

      <WithLabel :label="t('SUPPORT.NEW.ATTACHMENTS.LABEL')">
        <input
          type="file"
          multiple
          class="text-sm"
          :disabled="isSubmitting"
          @change="onFilesChange"
        />
      </WithLabel>

      <div>
        <NextButton
          blue
          type="submit"
          :is-loading="isSubmitting"
          :disabled="isFormInvalid"
        >
          {{ t('SUPPORT.NEW.SUBMIT') }}
        </NextButton>
      </div>
    </form>
  </div>
</template>
