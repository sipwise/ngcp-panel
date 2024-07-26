  function generate_password(len) {
    var text = "";
    var possible_lower = "abcdefghijklmnopqrstuvwxyz";
    var possible_upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    var possible_digit = "0123456789";
    var possible_spec = "@!?/\-_&*^%$;:<>,.()[]{}";
    var min_lower = 4;
    var min_upper = 4;
    var min_digit = 4;
    var min_spec = 4;
    var chars = ''
    for (var i = 0; i < min_lower; i++) {
        chars += possible_lower.charAt(Math.floor(Math.random() * possible_lower.length));
    }
    for (var i = 0; i < min_upper; i++) {
        chars += possible_upper.charAt(Math.floor(Math.random() * possible_upper.length));
    }
    for (var i = 0; i < min_digit; i++) {
        chars += possible_digit.charAt(Math.floor(Math.random() * possible_digit.length));
    }
    for (var i = 0; i < min_spec; i++) {
        chars += possible_spec.charAt(Math.floor(Math.random() * possible_spec.length));
    }
    return [...chars].sort(()=>Math.random()-.5).join('');
  }
  $(document).ready(function() {
    var btn = '<div id="gen_password" class="btn btn-primary pull-right" style="width:10%">Generate</div>';

    var passwd_btn = $(btn);
    var generated = '<div id="passwd_generated_text" style="width:10%; display:none; text-align:center">(modified)</div>';
    var passwd_generated = $(generated);
    passwd_btn.click(function() {
        $('input#password').val(generate_password(16));
        $('input#password').attr("style", "width: 70% !important");
        document.getElementById('passwd_generated_text').style.display = "inline-block";
    });
    $('input#password').attr("style", "width: 80% !important");
    $('input#password').after(passwd_generated);
    $('input#password').after(passwd_btn);

    var webpasswd_btn = $(btn);
    var generated = '<div id="webpasswd_generated_text" style="width:10%; display:none; text-align:center">(modified)</div>';
    var eye = '<div id="show_webpass" class="btn btn-info" style="display:inline-block" rel="tooltip" data-original-title="Show Web Password"><i id="show_webpass_icon" class="icon-eye-open" style="font-size:large"></i></div>';
    var webpasswd_generated = $(generated);
    var show_webpasswd = $(eye);
    webpasswd_btn.click(function() {
        $('input#webpassword').val(generate_password(16));
        $('input#webpassword').attr("style", "width: 65% !important");
        document.getElementById('webpasswd_generated_text').style.display = "inline-block";
    });
    show_webpasswd.click(function() {
        var webpass_input = document.getElementById("webpassword");
        if (webpass_input.type === "password") {
            webpass_input.type = "text";
            $('i#show_webpass_icon').attr("class", "icon-eye-close");
            $('div#show_webpass').attr("data-original-title", "Hide Web Password");
        }
        else {
            webpass_input.type = "password";
            $('i#show_webpass_icon').attr("class", "icon-eye-open");
            $('div#show_webpass').attr("data-original-title", "Show Web Password");
        }
    });
    $('input#webpassword').attr("style", "width: 75% !important");
    $('input#webpassword').after(show_webpasswd);
    $('input#webpassword').after(webpasswd_generated);
    $('input#webpassword').after(webpasswd_btn);
  });
