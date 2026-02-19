import LoginView from './Index.vue';

describe('LoginView signup link visibility', () => {
  afterEach(() => {
    window.chatwootConfig = {};
  });

  it('shows signup link when signupEnabled is boolean true', () => {
    window.chatwootConfig = { signupEnabled: true };

    expect(LoginView.computed.showSignupLink.call({})).toBe(true);
  });

  it('shows signup link when signupEnabled is string true', () => {
    window.chatwootConfig = { signupEnabled: 'true' };

    expect(LoginView.computed.showSignupLink.call({})).toBe(true);
  });

  it('hides signup link when signupEnabled is boolean false', () => {
    window.chatwootConfig = { signupEnabled: false };

    expect(LoginView.computed.showSignupLink.call({})).toBe(false);
  });

  it('hides signup link when signupEnabled is string false', () => {
    window.chatwootConfig = { signupEnabled: 'false' };

    expect(LoginView.computed.showSignupLink.call({})).toBe(false);
  });
});

