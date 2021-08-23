var Theme = function () {
    var chartColors, validationRules = getValidationRules ();

    // Black & Orange
    //chartColors = ["#FF9900", "#333", "#777", "#BBB", "#555", "#999", "#CCC"];

    // Ocean Breeze
    chartColors = ['#94BA65', '#2B4E72', '#2790B0', '#777','#555','#999','#bbb','#ccc','#eee'];

    // Fire Starter
    //chartColors = ['#750000', '#F90', '#777', '#555','#002646','#999','#bbb','#ccc','#eee'];

    // Mean Green
    //chartColors = ['#5F9B43', '#DB7D1F', '#BA4139', '#777','#555','#999','#bbb','#ccc','#eee'];

    return { init: init, chartColors: chartColors, createExpandCollapseButton: createExpandCollapseButton, validationRules: validationRules };

    function init () {
        enhancedAccordion ();

        if ($.fn.lightbox) {
            $('.ui-lightbox').lightbox();
        }

        if ($.fn.cirque) {
            $('.ui-cirque').cirque ({  });
        }

        $('#wrapper').append ('<div class="push"></div>');
    }

    function enhancedAccordion () {
        $('.accordion').on('show', function (e) {
             $(e.target).prev('.accordion-heading').parent ().addClass('open');
        });

        $('.accordion').on('hide', function (e) {
            if ($(e.target).hasClass('accordion-body')) {
                $(this).find('.accordion-toggle').not($(e.target)).parents ('.accordion-group').removeClass('open');
            }
        });

        $('.accordion').on('shown', function (e) {
            localStorage.setItem('lastTab', $(".accordion .in").attr('id'));
        });

        var lastTab = localStorage.getItem('lastTab');
        if (lastTab) {
            $('#'+lastTab).removeClass('collapse');
            $('#'+lastTab).parent().addClass("open");
            $('#'+lastTab).addClass("in");
        }

    }

    function createExpandCollapseButton (msg_collapse, msg_expand, framed) {
        if(!$('.accordion-body').length) return

        if(!$('#toggle-accordions').length) {
          if (framed) {
            $('#content').prepend('<a href="#" id="toggle-accordions" class="btn btn-small btn-tertiary pull-right ngcp-accordion-closed"><i class="icon-resize-full"></i>' + msg_expand + '</a>');
          } else {
            $('#content').children('.container').prepend('<a href="#" id="toggle-accordions" class="btn btn-small btn-tertiary pull-right ngcp-accordion-closed"><i class="icon-resize-full"></i>' + msg_expand + '</a>');
          }
        }

        $('#toggle-accordions').click(function() {
            if($('#toggle-accordions').hasClass('ngcp-accordion-closed')) {
                $('#toggle-accordions').removeClass('ngcp-accordion-closed');
                $('#toggle-accordions').html('<i class="icon-resize-small"></i> ' + msg_collapse);
                $('.accordion-body').each(function() {
                    $(this).removeClass('collapse');
                    $(this).parent().addClass("open");
                    $(this).addClass('in');
                    $(this).attr('style', 'height:auto;');
                });
                $('.accordion-heading a.accordion-toggle').each(function() {
                    $(this).removeClass('collapsed');
                });
                $('.accordion-group').each(function() {
                    $(this).addClass('open');
                });
            } else {
                $('#toggle-accordions').addClass('ngcp-accordion-closed');
                $('#toggle-accordions').html('<i class="icon-resize-full"></i> ' + msg_expand);
                $('.accordion-body').each(function() {
                    $(this).removeClass('in');
                    $(this).addClass('collapse');
                    $(this).attr('style', 'height:0px;');
                });
                $('.accordion-heading a.accordion-toggle').each(function() {
                    $(this).addClass('collapsed');
                });
                $('.accordion-group').each(function() {
                    $(this).removeClass('open');
                });
            }
        });
    }

    function getValidationRules () {
        var custom = {
            focusCleanup: false,

            wrapper: 'div',
            errorElement: 'span',

            highlight: function(element) {
                $(element).parents ('.control-group').removeClass ('success').addClass('error');
            },
            success: function(element) {
                $(element).parents ('.control-group').removeClass ('error').addClass('success');
                $(element).parents ('.controls:not(:has(.clean))').find ('div:last').before ('<div class="clean"></div>');
            },
            errorPlacement: function(error, element) {
                error.appendTo(element.parents ('.controls'));
            }
        };
        return custom;
    }

}();
