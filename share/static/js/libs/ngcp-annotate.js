(function( $ ) {

  $.fn.annotate = function(ctx) {

    return this.each(function(i, el) {
    
      var $el = $(el).attr("data-annotate", i);
      var pos = $el.attr("data-pos");
      if(pos == undefined) pos = "top";

      $el.append('<div class="arrow-' + pos + '"></div>');
      $el.addClass("annotate");

      //var linkPosition = $el.position();
      var linkPosition = {
        'top': $el.attr("data-pos-top"),
        'left': $el.attr("data-pos-left")
      };
      var top, left;
      switch(pos) {
      	case "top":
          top = linkPosition.top - 5 - $el.outerHeight();
          left = linkPosition.left - $el.outerWidth()/2;
	  break;
      	case "bottom":
          top = linkPosition.top - 15 + $el.outerHeight();
          left = linkPosition.left - $el.outerWidth()/2;
	  break;
      	case "left":
          top = linkPosition.top - $el.outerHeight()/2;
          left = linkPosition.left - 5 - $el.outerWidth();
	  break;
      	case "right":
          top = linkPosition.top - $el.outerHeight()/2;
          left = linkPosition.left + 5;
	  break;
      }
      $el.css({
        top: top,
        left: left
      });

    });

  }

})(jQuery);
