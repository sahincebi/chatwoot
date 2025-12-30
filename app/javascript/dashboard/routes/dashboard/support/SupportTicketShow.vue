<script setup>
import { ref, onMounted, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SupportTicketsAPI from 'dashboard/api/supportTickets';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const ticket = ref(null);
const isLoading = ref(true);
const isNotFound = ref(false);
const isSubmitting = ref(false);
const replyBody = ref('');
const files = ref([]);

const ticketId = computed(() => route.params.ticketId);

const hasReplyContent = computed(
  () => replyBody.value.trim().length > 0 || files.value.length > 0
);

const formatTimestamp = value => {
  if (!value) return '';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '' : date.toLocaleString();
};

const messageSenderLabel = message => {
  if (message.sender_type === 'SuperAdmin') return t('SUPPORT.SHOW.SUPPORT_TEAM');
  return t('SUPPORT.SHOW.YOU');
};

const onFilesChange = event => {
  files.value = Array.from(event.target.files || []);
};

const loadTicket = async () => {
  isLoading.value = true;
  isNotFound.value = false;
  try {
    const { data } = await SupportTicketsAPI.show(ticketId.value);
    ticket.value = data;
  } catch (error) {
    if (error?.response?.status === 404) {
      isNotFound.value = true;
    }
    // eslint-disable-next-line no-console
    console.error(error);
    useAlert(t('SUPPORT.SHOW.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const submitReply = async () => {
  if (isSubmitting.value || !hasReplyContent.value) return;

  isSubmitting.value = true;
  try {
    const payload = new FormData();
    payload.append('body', replyBody.value.trim());
    files.value.forEach(file => payload.append('attachments[]', file));

    await SupportTicketsAPI.createMessage(ticketId.value, payload);
    useAlert(t('SUPPORT.SHOW.REPLY_SUCCESS'));
    replyBody.value = '';
    files.value = [];
    await loadTicket();
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error(error);
    useAlert(error?.response?.data?.error || t('SUPPORT.SHOW.REPLY_ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};

onMounted(loadTicket);
</script>

<template>
  <div class="flex flex-col gap-6 p-6 max-w-4xl">
    <div class="flex items-center justify-between">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('SUPPORT.SHOW.TITLE') }}
      </h1>
      <NextButton
        outline
        @click="router.push({ name: 'support_ticket_index', params: { accountId: route.params.accountId } })"
      >
        {{ t('SUPPORT.SHOW.ALL_TICKETS') }}
      </NextButton>
    </div>

    <div v-if="isLoading" class="text-sm text-n-slate-11">
      {{ t('SUPPORT.SHOW.LOADING') }}
    </div>

    <template v-else>
      <div v-if="isNotFound" class="text-sm text-n-slate-11">
        {{ t('SUPPORT.SHOW.NOT_FOUND') }}
      </div>

      <div v-if="!ticket" class="text-sm text-n-slate-11">
        {{ t('SUPPORT.SHOW.LOAD_ERROR') }}
      </div>

      <template v-else-if="!isNotFound">
        <div class="grid grid-cols-1 gap-4 rounded-lg border border-n-weak bg-n-solid-1 p-4 text-sm">
          <div>
            <div class="text-n-slate-11">{{ t('SUPPORT.SHOW.SUBJECT') }}</div>
            <div class="text-n-slate-12 font-medium">{{ ticket.subject }}</div>
          </div>
          <div>
            <div class="text-n-slate-11">{{ t('SUPPORT.SHOW.DESCRIPTION') }}</div>
            <div class="text-n-slate-12 whitespace-pre-wrap">
              {{ ticket.description || ticket.messages?.[0]?.body || '-' }}
            </div>
          </div>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div>
              <div class="text-n-slate-11">{{ t('SUPPORT.SHOW.STATUS') }}</div>
              <div class="text-n-slate-12">{{ ticket.status }}</div>
            </div>
            <div>
              <div class="text-n-slate-11">{{ t('SUPPORT.SHOW.CATEGORY') }}</div>
              <div class="text-n-slate-12">{{ ticket.category || '-' }}</div>
            </div>
            <div>
              <div class="text-n-slate-11">{{ t('SUPPORT.SHOW.PRIORITY') }}</div>
              <div class="text-n-slate-12">{{ ticket.priority }}</div>
            </div>
          </div>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div>
              <div class="text-n-slate-11">{{ t('SUPPORT.SHOW.REQUESTER') }}</div>
              <div class="text-n-slate-12">
                {{
                  (ticket.requester && (ticket.requester.email || ticket.requester.name)) || '-'
                }}
              </div>
            </div>
            <div>
              <div class="text-n-slate-11">{{ t('SUPPORT.SHOW.CREATED_AT') }}</div>
              <div class="text-n-slate-12">{{ formatTimestamp(ticket.created_at) }}</div>
            </div>
            <div>
              <div class="text-n-slate-11">{{ t('SUPPORT.SHOW.LAST_ACTIVITY') }}</div>
              <div class="text-n-slate-12">{{ formatTimestamp(ticket.last_activity_at) }}</div>
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12">
            {{ t('SUPPORT.SHOW.MESSAGES') }}
          </h2>
          <div v-if="ticket.messages && ticket.messages.length" class="space-y-3">
            <div
              v-for="message in ticket.messages"
              :key="message.id"
              class="rounded-lg border border-n-weak bg-white p-3"
            >
              <div class="text-xs text-n-slate-11 mb-2">
                {{ messageSenderLabel(message) }}
                <span v-if="message.created_at">- {{ formatTimestamp(message.created_at) }}</span>
              </div>
              <div class="text-sm text-n-slate-12 whitespace-pre-wrap">
                {{ message.body }}
              </div>
              <div
                v-if="message.attachments && message.attachments.length"
                class="mt-2 text-xs text-n-slate-11"
              >
                {{ t('SUPPORT.SHOW.ATTACHMENTS') }}:
                <div class="mt-1 flex flex-wrap gap-2">
                  <a
                    v-for="file in message.attachments"
                    :key="file.id"
                    :href="file.url"
                    class="text-woot-500 hover:text-woot-700"
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {{ file.filename }}
                  </a>
                </div>
              </div>
            </div>
          </div>
          <div v-else class="text-sm text-n-slate-11">
            -
          </div>
        </div>

        <div class="rounded-lg border border-n-weak bg-n-solid-1 p-4">
          <h2 class="text-sm font-semibold text-n-slate-12 mb-3">
            {{ t('SUPPORT.SHOW.REPLY') }}
          </h2>
          <WithLabel name="reply_body" :label="t('SUPPORT.SHOW.REPLY')">
            <textarea
              v-model="replyBody"
              rows="4"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-12"
              :placeholder="t('SUPPORT.SHOW.REPLY_PLACEHOLDER')"
              :disabled="isSubmitting"
            />
          </WithLabel>
          <WithLabel
            name="reply_attachments"
            :label="t('SUPPORT.SHOW.ATTACHMENTS')"
            class="mt-3"
          >
            <input
              type="file"
              multiple
              class="text-sm"
              :disabled="isSubmitting"
              @change="onFilesChange"
            />
          </WithLabel>
          <div class="mt-4">
            <NextButton
              blue
              :is-loading="isSubmitting"
              :disabled="!hasReplyContent || isSubmitting"
              @click="submitReply"
            >
              {{ t('SUPPORT.SHOW.SEND_REPLY') }}
            </NextButton>
          </div>
        </div>
      </template>
    </template>
  </div>
</template>




