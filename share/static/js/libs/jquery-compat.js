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

(function($) {
    var $old = $;
    window.$ = window.jQuery = function(selector, context) {
        if (selector === '#' || selector === '') {
            console.warn('jquery # override');
            return $old([]);
        }
        return $old(selector, context);
    };
})(jQuery);