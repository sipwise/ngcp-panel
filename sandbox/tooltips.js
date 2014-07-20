(function( $ ) {

  $.fn.tooltips = function(el) {

    var $tooltip,
      $body = $('body'),
      $el;

    return this.each(function(i, el) {
    
      $el = $(el).attr("data-tooltip", i);
      var pos = $el.attr("data-pos");
      if(pos == undefined) pos = "top";
      console.log("pos at " + i + " is ", pos);

      var $tooltip = $('<div class="tooltip" data-tooltip="' + i + '">' + $el.html() + '<div class="arrow-' + pos + '"></div></div>').appendTo("body");
      $el.html('');

      var linkPosition = $el.position();
      console.log(linkPosition);
      console.log("w="+$tooltip.outerWidth()+",h="+$tooltip.outerHeight());
      var top, left;
      switch(pos) {
      	case "top":
          top = linkPosition.top + 10 - $tooltip.outerHeight();
          left = linkPosition.left + 48 - $tooltip.outerWidth()/2;
	  break;
      	case "bottom":
          top = linkPosition.top + 3 + $tooltip.outerHeight();
          left = linkPosition.left + 48 - $tooltip.outerWidth()/2;
	  break;
      	case "left":
          top = linkPosition.top + 17 - ($tooltip.outerHeight()/2);
          left = linkPosition.left + 41 - $tooltip.outerWidth();
	  break;
      	case "right":
          top = linkPosition.top + 17 - ($tooltip.outerHeight()/2);
          left = linkPosition.left + 55;
	  break;
      }
      $tooltip.css({
        top: top,
        left: left
      });

    });

  }

})(jQuery);
