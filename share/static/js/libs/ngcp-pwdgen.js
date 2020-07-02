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
    var generated = '<div id="passwd_generated_text" style="width:10%; display:none; text-align:center">(modified)</div>';
    var passwd_generated = $(generated);
    passwd_btn.click(function() {
        $('input#password').val(generate_password(16));
        $('input#password').attr("style", "width: 75% !important");
        document.getElementById('passwd_generated_text').style.display = "inline-block";
    });
    $('input#password').attr("style", "width: 80% !important");
    $('input#password').after(passwd_generated);
    $('input#password').after(passwd_btn);

    var webpasswd_btn = $(btn);
    var generated = '<div id="webpasswd_generated_text" style="width:10%; display:none; text-align:center">(modified)</div>';
    var webpasswd_generated = $(generated);
    webpasswd_btn.click(function() {
        $('input#webpassword').val(generate_password(16));
        $('input#webpassword').attr("style", "width: 75% !important");
        document.getElementById('webpasswd_generated_text').style.display = "inline-block";
    });
    $('input#webpassword').attr("style", "width: 80% !important");
    $('input#webpassword').after(webpasswd_generated);
    $('input#webpassword').after(webpasswd_btn);
  });
