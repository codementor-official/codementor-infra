<#-- One look for every account email: same header, footer and colours as the app's reminder emails. -->
<#macro emailLayout title="" preheader="">
<!doctype html>
<html lang="vi">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head>
<body style="margin:0;padding:0;background:#f4f4f5;color:#18181b;font-family:Inter,Segoe UI,Roboto,Helvetica,Arial,sans-serif">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">${preheader}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f4f5"><tr><td align="center" style="padding:28px 12px">
<table role="presentation" width="600" cellspacing="0" cellpadding="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:14px;overflow:hidden;border:1px solid #e5e7eb">
 <tr><td style="background:#18181b;padding:20px 28px">
  <table role="presentation" cellspacing="0" cellpadding="0"><tr>
   <td style="vertical-align:middle"><img src="https://codementor.cloud/brand-mark-dark.png" width="40" height="40" alt="CodeMentor" style="display:block;border:0"></td>
   <td style="vertical-align:middle;padding-left:12px">
    <div style="font-size:20px;font-weight:700;color:#ffffff">Code<span style="color:#ea580c">Mentor</span></div>
    <div style="font-size:11px;color:#a1a1aa;letter-spacing:1px;text-transform:uppercase">Học tốt hơn · Lập trình tự tin hơn</div>
   </td></tr></table>
 </td></tr>
 <tr><td style="height:4px;background:#ea580c;line-height:4px;font-size:0">&nbsp;</td></tr>
 <tr><td style="padding:28px 28px 26px;font-size:15px;line-height:1.7">
  <span style="display:inline-block;background:#fff7ed;color:#c2410c;font-size:12px;font-weight:700;padding:4px 10px;border-radius:999px">Tài khoản</span>
  <h1 style="font-size:22px;line-height:1.35;margin:14px 0 18px;color:#18181b">${title}</h1>
  <#nested>
 </td></tr>
 <tr><td style="padding:18px 28px;background:#fafafa;border-top:1px solid #e5e7eb;font-size:12px;line-height:1.7;color:#6b7280">
  Email này được gửi vì có thao tác với tài khoản CodeMentor của bạn. Nếu không phải bạn, hãy bỏ qua email; tài khoản của bạn vẫn an toàn.<br>
  Đây là email tự động, vui lòng không trả lời. Cần hỗ trợ? Liên hệ <a href="mailto:codementor.official@gmail.com" style="color:#c2410c">codementor.official@gmail.com</a>.
 </td></tr>
 <tr><td style="padding:16px 28px 22px;background:#18181b;font-size:12px;line-height:1.7;color:#a1a1aa">
  <strong style="color:#ffffff">CodeMentor</strong> — nền tảng học lập trình với lộ trình rõ ràng, bài tập chấm tự động, trợ lý AI và nhóm học tập.<br>
  <a href="https://codementor.cloud" style="color:#ea580c">codementor.cloud</a>
 </td></tr>
</table></td></tr></table>
</body></html>
</#macro>

<#-- The call to action: orange button plus the raw link for clients that block buttons. -->
<#macro button link label>
<p style="margin:22px 0 6px"><a href="${link}" style="display:inline-block;background:#ea580c;color:#ffffff;font-size:15px;font-weight:700;padding:13px 24px;border-radius:8px;text-decoration:none">${label} &rarr;</a></p>
<p style="margin:10px 0 0;font-size:12px;line-height:1.6;color:#6b7280">Nút không hoạt động? Mở liên kết này: <a href="${link}" style="color:#c2410c;word-break:break-all">${link}</a></p>
</#macro>

<#macro note text>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:18px;background:#fafafa;border:1px solid #e5e7eb;border-left:4px solid #ea580c;border-radius:8px"><tr><td style="padding:12px 16px;font-size:14px;line-height:1.6">${text}</td></tr></table>
</#macro>
