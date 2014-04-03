/*
http://stackoverflow.com/questions/1184624/convert-form-data-to-js-object-with-jquery
*/

(function ($) {
$.fn.serializeObject = function()
{
    var o = {};
    $.each(this.serializeArray(), function() {
        if (o[this.name] !== undefined) {
            if (!o[this.name].push) {
                o[this.name] = [o[this.name]];
            }
            o[this.name].push(this.value || '');
        } else {
            o[this.name] = this.value || '';
        }
    });
    return o;
};})(jQuery);