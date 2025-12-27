const getDefaultFaviconUrl = () => {
  const globalConfig = window.globalConfig || {};
  return globalConfig.FAVICON_URL || document.querySelector('.favicon')?.href;
};

const setFaviconHref = () => {
  const favicons = document.querySelectorAll('.favicon');
  const faviconUrl = getDefaultFaviconUrl();
  if (!faviconUrl) return;

  favicons.forEach(favicon => {
    favicon.href = faviconUrl;
  });
};

export const showBadgeOnFavicon = () => {
  setFaviconHref();
};

export const initFaviconSwitcher = () => {
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      setFaviconHref();
    }
  });
};
