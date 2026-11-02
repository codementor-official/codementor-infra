<#import "template.ftl" as layout>
<#assign actions><#if requiredActions??><#list requiredActions as reqActionItem>${msg("requiredAction.${reqActionItem}")}<#sep>, </#sep></#list></#if></#assign>
<@layout.emailLayout title="Cập nhật tài khoản" preheader="Quản trị viên yêu cầu bạn cập nhật tài khoản CodeMentor.">
<p style="margin:0 0 12px">Chào <strong>${user.firstName!user.username}</strong>,</p>
<p style="margin:0">Quản trị viên CodeMentor yêu cầu bạn hoàn tất: <strong>${actions}</strong>.</p>
<@layout.button link=link label="Cập nhật tài khoản"/>
<@layout.note text="Liên kết có hiệu lực trong ${linkExpirationFormatter(linkExpiration)}."/>
</@layout.emailLayout>
