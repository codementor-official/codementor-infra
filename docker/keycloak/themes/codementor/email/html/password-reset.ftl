<#import "template.ftl" as layout>
<@layout.emailLayout title="Đặt lại mật khẩu" preheader="Yêu cầu đặt lại mật khẩu tài khoản CodeMentor.">
<p style="margin:0 0 12px">Chào <strong>${user.firstName!user.username}</strong>,</p>
<p style="margin:0">Chúng tôi nhận được yêu cầu đặt lại mật khẩu cho tài khoản CodeMentor gắn với email này. Bấm nút bên dưới để chọn mật khẩu mới.</p>
<@layout.button link=link label="Đặt mật khẩu mới"/>
<@layout.note text="Liên kết có hiệu lực trong ${linkExpirationFormatter(linkExpiration)} và chỉ dùng được một lần. Nếu bạn không yêu cầu, hãy bỏ qua email này: mật khẩu hiện tại vẫn giữ nguyên."/>
</@layout.emailLayout>
