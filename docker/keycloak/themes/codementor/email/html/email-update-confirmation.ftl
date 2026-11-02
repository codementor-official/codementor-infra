<#import "template.ftl" as layout>
<@layout.emailLayout title="Xác nhận email mới" preheader="Xác nhận đổi email đăng nhập CodeMentor.">
<p style="margin:0 0 12px">Chào <strong>${user.firstName!user.username}</strong>,</p>
<p style="margin:0">Bạn vừa yêu cầu dùng <strong>${newEmail}</strong> làm email đăng nhập CodeMentor. Bấm nút bên dưới để xác nhận.</p>
<@layout.button link=link label="Xác nhận email mới"/>
<@layout.note text="Liên kết có hiệu lực trong ${linkExpirationFormatter(linkExpiration)}. Nếu bạn không yêu cầu đổi email, hãy bỏ qua email này."/>
</@layout.emailLayout>
