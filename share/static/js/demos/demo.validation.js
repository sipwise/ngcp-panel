$(function () {
  var rules = {
    rules: {
      name: { minlength: 2, required: true },
      email: { required: true, email: true },
      subject: { minlength: 2, required: true },
      message: { minlength: 2, required: true },
      validateSelect: { required: true },
      validateCheckbox: { required: true, minlength: 2},
      validateRadio: { required: true },

      bilprof_select: { required: true },
      username: { minlength: 4, required: true },
      password: { minlength: 4, required: true },
    }
  };
  var validationObj = $.extend (rules, Theme.validationRules);
  $('form').validate(validationObj);
});
