export const isTruthyConfigValue = value => {
  if (value === true) return true;
  if (value === false || value === null || value === undefined) return false;

  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return ['true', '1', 'yes', 'on'].includes(normalized);
  }

  if (typeof value === 'number') {
    return value === 1;
  }

  return Boolean(value);
};

