<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ContactAPI from 'dashboard/api/contacts';
import { DuplicateContactException } from 'shared/helpers/CustomErrors';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const subject = ref('');
const category = ref('technical');
const priority = ref('normal');
const description = ref('');
const files = ref([]);
const isSubmitting = ref(false);
const supportInboxId = ref(null);

const currentUser = useMapGetter('getCurrentUser');
const currentAccount = useMapGetter('getCurrentAccount');
const inboxes = useMapGetter('inboxes/getInboxes');

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

const selectedCategoryLabel = computed(() => {
  return (
    categoryOptions.value.find(option => option.value === category.value)
      ?.label || category.value
  );
});

const selectedPriorityLabel = computed(() => {
  return (
    priorityOptions.value.find(option => option.value === priority.value)
      ?.label || priority.value
  );
});

const isInboxMissing = computed(() => !supportInboxId.value);
const isFormInvalid = computed(
  () =>
    isSubmitting.value ||
    isInboxMissing.value ||
    !subject.value.trim() ||
    !description.value.trim()
);

const updateSupportInbox = () => {
  const inbox = inboxes.value.find(item =>
    (item.name || '').toLowerCase().includes('destek')
  );
  supportInboxId.value = inbox?.id ?? null;
};

const onFilesChange = event => {
  files.value = Array.from(event.target.files || []);
};

const buildSupportMessage = () => {
  const accountId = route.params.accountId;
  const accountName = currentAccount.value?.name || '';
  const userName = currentUser.value?.name || currentUser.value?.email || '';
  const userEmail = currentUser.value?.email || '';

  return t('SUPPORT.NEW.MESSAGE_TEMPLATE', {
    subject: subject.value.trim(),
    category: selectedCategoryLabel.value,
    priority: selectedPriorityLabel.value,
    accountName,
    accountId,
    userName,
    userEmail,
    description: description.value.trim(),
  });
};

const findOrCreateContact = async () => {
  const userEmail = currentUser.value?.email?.trim();
  if (!userEmail) {
    throw new Error('missing_email');
  }
  const {
    data: { payload = [] },
  } = await ContactAPI.search(userEmail);
  const normalizedEmail = userEmail.toLowerCase();
  const existing =
    payload.find(
      contact => (contact.email || '').toLowerCase() === normalizedEmail
    ) || payload[0];

  if (existing?.id) {
    return existing.id;
  }

  try {
    const contact = await store.dispatch('contacts/create', {
      name: currentUser.value?.name || userEmail,
      email: userEmail,
      additionalAttributes: {
        source: 'dashboard_support',
        userId: currentUser.value?.id,
      },
    });
    return contact?.id;
  } catch (error) {
    if (error instanceof DuplicateContactException) {
      const {
        data: { payload: retryPayload = [] },
      } = await ContactAPI.search(userEmail);
      const retryContact =
        retryPayload.find(
          contact => (contact.email || '').toLowerCase() === normalizedEmail
        ) || retryPayload[0];
      if (retryContact?.id) {
        return retryContact.id;
      }
    }
    throw error;
  }
};

const submitTicket = async () => {
  if (isFormInvalid.value) return;
  isSubmitting.value = true;
  try {
    const contactId = await findOrCreateContact();
    const payload = {
      inboxId: supportInboxId.value,
      contactId,
      sourceId: `support_ticket_${Date.now()}`,
      mailSubject: subject.value.trim(),
      message: { content: buildSupportMessage() },
      files: files.value,
    };

    const conversation = await store.dispatch('contactConversations/create', {
      params: payload,
      isFromWhatsApp: false,
    });

    useAlert(t('SUPPORT.NEW.SUCCESS'));
    await router.push({
      name: 'inbox_conversation',
      params: {
        accountId: route.params.accountId,
        conversation_id: conversation?.id,
      },
    });
  } catch (error) {
    useAlert(t('SUPPORT.NEW.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};

onMounted(async () => {
  if (!inboxes.value.length) {
    await store.dispatch('inboxes/get');
  }
  updateSupportInbox();
});
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

    <div
      v-if="isInboxMissing"
      class="rounded-lg border border-n-weak bg-n-solid-3 px-4 py-3 text-sm text-n-slate-11"
    >
      {{ t('SUPPORT.NEW.NO_INBOX') }}
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
