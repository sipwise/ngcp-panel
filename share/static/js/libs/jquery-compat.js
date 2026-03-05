jQuery.uaMatch = function( ua ) {
    ua = ua.toLowerCase();
    var match = /(chrome)[ \/]([\w.]+)/.exec( ua ) ||
        /(webkit)[ \/]([\w.]+)/.exec( ua ) ||
        /(opera)(?:.*version|)[ \/]([\w.]+)/.exec( ua ) ||
        /(msie) ([\w.]+)/.exec( ua ) ||
        ua.indexOf("compatible") < 0 && /(mozilla)(?:.*? rv:([\w.]+)|)/.exec( ua ) ||
        [];

    return {
        browser: match[ 1 ] || "",
        version: match[ 2 ] || "0"
    };
};

var matched = jQuery.uaMatch( navigator.userAgent );
jQuery.browser = {};
if ( matched.browser ) {
    jQuery.browser[ matched.browser ] = true;
    jQuery.browser.version = matched.version;
}

(function ($) {

    const booleanAttrs = {
        checked: true,
        selected: true,
        disabled: true,
        readonly: true,
        multiple: true
    };

    var oldInit = $.fn.init;

    $.fn.init = function (selector, context, root) {

        if (typeof selector === 'string') {
            if (selector === '#' || selector.trim() === '') {
                console.warn('jquery # override', new Error().stack);
                return oldInit.call(this, [], context, root);
            }
        }

        return oldInit.call(this, selector, context, root);
    };

    $.fn.init.prototype = $.fn;

    const oldAttr = $.fn.attr;

    $.fn.attr = function (name, value) {

        if (booleanAttrs[name]) {

            // getter
            if (value === undefined) {
                return this.prop(name) ? name : undefined;
            }

            // setter
            return this.prop(name, !!value);
        }

        return oldAttr.apply(this, arguments);
    };

})(jQuery);