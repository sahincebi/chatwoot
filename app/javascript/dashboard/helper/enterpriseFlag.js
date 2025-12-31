export function isEnterpriseEnabled() {
  const raw =
    window?.chatwootConfig?.isEnterprise ??
    window?.globalConfig?.isEnterprise ??
    window?.globalConfig?.IS_ENTERPRISE;

  return raw === true || raw === 'true' || raw === 1 || raw === '1';
}
