(function( $ ) {

  $.fn.annotate = function(ctx) {

    console.log("ctx is ", ctx);

    var $annotate,
      $body = $('body'),
      $el;

    return this.each(function(i, el) {
    
      $el = $(el).attr("data-annotate", i);
      var pos = $el.attr("data-pos");
      if(pos == undefined) pos = "top";
      console.log("pos at " + i + " is ", pos);

      var $annotate = $('<div class="annotate ' + $el.attr("class") + '" data-annotate="' + i + '">' + $el.html() + '<div class="arrow-' + pos + '"></div></div>');
      $(ctx).append($annotate);

      $el.html('');

      var linkPosition = $el.position();
      var top, left;
      switch(pos) {
      	case "top":
          top = linkPosition.top - 5 - $annotate.outerHeight();
          left = linkPosition.left - 9 - $annotate.outerWidth()/2;
	  break;
      	case "bottom":
          top = linkPosition.top - 11 + $annotate.outerHeight();
          left = linkPosition.left - 9 - $annotate.outerWidth()/2;
	  break;
      	case "left":
          top = linkPosition.top - ($annotate.outerHeight()/2);
          left = linkPosition.left - 25 - $annotate.outerWidth();
	  break;
      	case "right":
          top = linkPosition.top - ($annotate.outerHeight()/2);
          left = linkPosition.left + 5;
	  break;
      }
      $annotate.css({
        top: top,
        left: left
      });

    });

  }

})(jQuery);
