<#import "template.ftl" as layout>
<@layout.emailLayout title="Xác nhận địa chỉ email" preheader="Xác nhận email để bắt đầu học trên CodeMentor.">
<p style="margin:0 0 12px">Chào <strong>${user.firstName!user.username}</strong>,</p>
<p style="margin:0">Cảm ơn bạn đã đăng ký CodeMentor. Hãy xác nhận đây là email của bạn để nhận nhắc hạn nộp, thông báo nhóm học tập và khôi phục tài khoản khi cần.</p>
<@layout.button link=link label="Xác nhận email"/>
<@layout.note text="Liên kết có hiệu lực trong ${linkExpirationFormatter(linkExpiration)}. Hết hạn thì bạn có thể yêu cầu gửi lại trong phần Tài khoản."/>
</@layout.emailLayout>
