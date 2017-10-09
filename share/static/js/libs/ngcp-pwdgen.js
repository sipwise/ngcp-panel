  function generate_password(len) {
    var text = "";
    var possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!?/-_%$()[]";
    for (var i = 0; i < len; i++) {
        text += possible.charAt(Math.floor(Math.random() * possible.length));
    }
    return text;
  }
  $(document).ready(function() {
    var btn = '<div id="gen_password" class="btn btn-primary pull-right" style="width:10%">Generate</div>';

    var passwd_btn = $(btn);
    passwd_btn.click(function() {
        $('input#password').val(generate_password(16));
    });
    $('input#password').attr("style", "width: 80% !important");
    $('input#password').after(passwd_btn);

    var webpasswd_btn = $(btn);
    webpasswd_btn.click(function() {
        $('input#webpassword').val(generate_password(16));
    });
    $('input#webpassword').attr("style", "width: 80% !important");
    $('input#webpassword').after(webpasswd_btn);
  });
