(function( $ ) {

  $.fn.annotate = function(el) {

    var $annotate,
      $body = $('body'),
      $el;

    return this.each(function(i, el) {
    
      $el = $(el).attr("data-annotate", i);
      var pos = $el.attr("data-pos");
      if(pos == undefined) pos = "top";
      console.log("pos at " + i + " is ", pos);

      var $annotate = $('<div class="annotate ' + $el.attr("class") + '" data-annotate="' + i + '">' + $el.html() + '<div class="arrow-' + pos + '"></div></div>').appendTo("body");
      $el.html('');

      var linkPosition = $el.position();
      console.log(linkPosition);
      console.log("w="+$annotate.outerWidth()+",h="+$annotate.outerHeight());
      var top, left;
      switch(pos) {
      	case "top":
          top = linkPosition.top + 10 - $annotate.outerHeight();
          left = linkPosition.left + 48 - $annotate.outerWidth()/2;
	  break;
      	case "bottom":
          top = linkPosition.top + 3 + $annotate.outerHeight();
          left = linkPosition.left + 48 - $annotate.outerWidth()/2;
	  break;
      	case "left":
          top = linkPosition.top + 17 - ($annotate.outerHeight()/2);
          left = linkPosition.left + 41 - $annotate.outerWidth();
	  break;
      	case "right":
          top = linkPosition.top + 17 - ($annotate.outerHeight()/2);
          left = linkPosition.left + 55;
	  break;
      }
      $annotate.css({
        top: top,
        left: left
      });

    });

  }

})(jQuery);
