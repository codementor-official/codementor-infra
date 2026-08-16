// Mirrors the `useState(showPassword)` toggle in apps/web's original AuthCard —
// same behavior, plain JS since this page has no React runtime.
document.querySelectorAll(".cm-toggle-password").forEach(function (button) {
  button.addEventListener("click", function () {
    var input = document.getElementById(button.dataset.target);
    var showing = input.type === "text";
    input.type = showing ? "password" : "text";
    button.querySelector(".cm-eye-on").hidden = !showing;
    button.querySelector(".cm-eye-off").hidden = showing;
    button.setAttribute("aria-label", showing ? "Hiện mật khẩu" : "Ẩn mật khẩu");
  });
});
