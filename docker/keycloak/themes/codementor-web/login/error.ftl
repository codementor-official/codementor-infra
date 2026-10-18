<#-- Trang lỗi của popup đăng nhập Google/Facebook.

     Tài khoản bị admin tạm khoá thì Keycloak dừng ở đây thay vì quay về app. Trang này báo
     bằng giao diện CodeMentor (khung đỏ + email kháng cáo), gửi tín hiệu
     `codementor:account-suspended` cho cửa sổ đã mở popup để trang đăng nhập của app hiện cùng
     thông báo, rồi tự đóng. Tín hiệu không mang dữ liệu gì; app chỉ nhận nó từ origin Keycloak.
     Các lỗi khác vẫn hiện nguyên câu của Keycloak. -->
<#assign suspended = (message?? && message.summary?? && message.summary == msg("accountDisabledMessage"))>
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
      <#if suspended>
        <h1 class="cm-title">Tài khoản đang bị tạm khoá</h1>
        <div class="cm-alert cm-alert-error">
          Tài khoản bị khoá do nội dung vi phạm quy định của CodeMentor. Nếu bạn cho rằng đây là nhầm
          lẫn và muốn kháng cáo, hãy liên hệ
          <a class="cm-link-strong" href="mailto:codementor.official@gmail.com">codementor.official@gmail.com</a>.
        </div>
        <script>
          if (window.opener) {
            window.opener.postMessage({ type: "codementor:account-suspended" }, "*");
            window.close();
          }
        </script>
      <#else>
        <h1 class="cm-title">Đã có lỗi xảy ra</h1>
        <#if message?? && message.summary??>
          <div class="cm-alert cm-alert-error">${kcSanitize(message.summary)?no_esc}</div>
        </#if>
      </#if>
      <#if client?? && client.baseUrl?has_content>
        <p class="cm-footer"><a class="cm-link" href="${client.baseUrl}">Quay lại CodeMentor</a></p>
      </#if>
    </div>
  </div>
</body>
</html>
