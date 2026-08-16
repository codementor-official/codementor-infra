<#-- Custom login page: NOT built on keycloak.v2's registrationLayout macro on purpose.
     That macro renders PatternFly's 2-column login grid, which is a different DOM
     shape than apps/web's AuthCard (commit b975182) — no amount of CSS makes one
     look exactly like the other. This file owns the full HTML instead, using only
     Keycloak's stable FreeMarker context (realm/url/login/social/message/msg) so
     the DOM can match AuthCard's structure directly. Other pages (register, forgot
     password, errors, ...) still fall back to the parent theme — see theme.properties. -->
<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>CodeMentor</title>
  <link rel="stylesheet" href="${url.resourcesPath}/css/login.css" />
</head>
<body>
  <div class="cm-page">
    <div class="cm-card">
      <h1 class="cm-title">Chào mừng trở lại!</h1>

      <div class="cm-tabs">
        <span class="cm-tab cm-tab-active">Đăng nhập</span>
        <#if realm.registrationAllowed && !registrationDisabled??>
          <a class="cm-tab" href="${url.registrationUrl}">Đăng ký</a>
        </#if>
      </div>

      <#if social?? && social.providers??>
        <div class="cm-social">
          <#list social.providers as p>
            <a id="social-${p.alias}" class="cm-social-btn" href="${p.loginUrl}">
              <span class="cm-social-badge">${p.alias?substring(0,1)?upper_case}</span>
              Tiếp tục với ${p.displayName}
            </a>
          </#list>
        </div>

        <div class="cm-divider"><span></span>hoặc<span></span></div>
      </#if>

      <#if message?? && message.summary??>
        <div class="cm-alert cm-alert-${message.type}">${kcSanitize(message.summary)?no_esc}</div>
      </#if>

      <#if realm.password>
        <form class="cm-form" id="kc-form-login" action="${url.loginAction}" method="post">
          <div class="cm-field">
            <label for="username" class="cm-label">
              <#if !realm.loginWithEmailAllowed>Tên đăng nhập<#elseif !realm.registrationEmailAsUsername>Email hoặc tên đăng nhập<#else>Email</#if>
            </label>
            <div class="cm-input-wrap">
              <svg class="cm-input-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4h16v16H4z" opacity="0"/><path d="M4 6h16v12H4z"/><path d="m4 7 8 6 8-6"/></svg>
              <input id="username" name="username" type="text" class="cm-input cm-input-icon-l"
                     value="${(login.username!'')}" autofocus autocomplete="username"
                     placeholder="ban@codementor.dev" />
            </div>
          </div>

          <div class="cm-field">
            <label for="password" class="cm-label">Mật khẩu</label>
            <div class="cm-input-wrap">
              <svg class="cm-input-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>
              <input id="password" name="password" type="password" class="cm-input cm-input-icon-l cm-input-icon-r"
                     autocomplete="current-password" placeholder="••••••••" />
              <button type="button" class="cm-toggle-password" data-target="password" aria-label="Hiện mật khẩu">
                <svg class="cm-eye-on" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7Z"/><circle cx="12" cy="12" r="3"/></svg>
                <svg class="cm-eye-off" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" hidden><path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 7 11 7a13.16 13.16 0 0 1-1.67 2.68M6.61 6.61C3.35 8.36 1 11.5 1 12s4 7 11 7a9.26 9.26 0 0 0 5.39-1.61M14.12 14.12a3 3 0 1 1-4.24-4.24"/><path d="M1 1l22 22"/></svg>
              </button>
            </div>
          </div>

          <div class="cm-row-between">
            <#if realm.rememberMe && !usernameEditDisabled??>
              <label class="cm-remember">
                <input type="checkbox" name="rememberMe" id="rememberMe" <#if login.rememberMe??>checked</#if> />
                Ghi nhớ đăng nhập
              </label>
            <#else>
              <span></span>
            </#if>
            <#if realm.resetPasswordAllowed>
              <a class="cm-link" href="${url.loginResetCredentialsUrl}">Quên mật khẩu?</a>
            </#if>
          </div>

          <input type="hidden" id="id-hidden-input" name="credentialId"
                 <#if auth?has_content && auth.selectedCredential?has_content>value="${auth.selectedCredential}"</#if> />
          <button type="submit" name="login" id="kc-login" class="cm-submit">Đăng nhập</button>
        </form>
      </#if>

      <#if realm.password && realm.registrationAllowed && !registrationDisabled??>
        <p class="cm-footer">
          Chưa có tài khoản?
          <a class="cm-link-strong" href="${url.registrationUrl}">Đăng ký</a>
        </p>
      </#if>
    </div>
  </div>
  <script src="${url.resourcesPath}/js/toggle-password.js"></script>
</body>
</html>
