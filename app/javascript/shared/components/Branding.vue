<script>
const {
  LOGO_THUMBNAIL: logoThumbnail,
  BRAND_NAME: brandName,
  INSTALLATION_NAME: installationName,
  WIDGET_BRAND_URL: widgetBrandURL,
} = window.globalConfig || {};

export default {
  props: {
    disableBranding: {
      type: Boolean,
      default: false,
    },
  },
  data() {
    return {
      globalConfig: {
        brandName,
        installationName,
        logoThumbnail,
        widgetBrandURL,
      },
    };
  },
  computed: {
    displayBrandName() {
      return this.globalConfig.brandName || this.globalConfig.installationName;
    },
    brandRedirectURL() {
      try {
        const referrerHost = this.$store.getters['appConfig/getReferrerHost'];
        const url = new URL(this.globalConfig.widgetBrandURL);
        if (referrerHost) {
          url.searchParams.set('utm_source', referrerHost);
          url.searchParams.set('utm_medium', 'widget');
        } else {
          url.searchParams.set('utm_medium', 'survey');
        }
        url.searchParams.set('utm_campaign', 'branding');
        return url.toString();
      } catch (e) {
        // Suppressing the error as getter is not defined in some cases
      }
      return '';
    },
  },
};
</script>

<template>
  <div v-if="displayBrandName && !disableBranding" class="px-0 py-3 flex justify-center">
    <a
      :href="brandRedirectURL"
      rel="noreferrer noopener nofollow"
      target="_blank"
      class="branding--link text-n-slate-11 hover:text-n-slate-12 cursor-pointer text-xs inline-flex grayscale-[1] hover:grayscale-0 hover:opacity-100 opacity-90 no-underline justify-center items-center leading-3"
    >
      <img
        class="ltr:mr-1 rtl:ml-1 max-w-3 max-h-3"
        :alt="displayBrandName"
        :src="globalConfig.logoThumbnail"
      />
      <span>
        {{ $t('POWERED_BY', { brand_name: displayBrandName }) }}
      </span>
    </a>
  </div>
  <div v-else class="p-3" />
</template>
