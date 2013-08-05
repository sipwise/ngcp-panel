$.extend($.fn.dataTableExt.oStdClasses, {
    'sPageEllipsis': 'paginate_ellipsis',
    'sPageNumber': 'paginate_number',
    'sPageNumbers': 'paginate_numbers'
});
 
$.fn.dataTableExt.oPagination.bootstrap = {
    'oDefaults': {
        'iShowPages': 5
    },
    'fnClickHandler': function(e) {
        var fnCallbackDraw = e.data.fnCallbackDraw,
            oSettings = e.data.oSettings,
            sPage = e.data.sPage;
 
        if ($(this).is('[disabled]')) {
            return false;
        }
 
        oSettings.oApi._fnPageChange(oSettings, sPage);
        fnCallbackDraw(oSettings);
 
        return true;
    },
    // fnInit is called once for each instance of pager
    'fnInit': function(oSettings, nPager, fnCallbackDraw) {
        var oClasses = oSettings.oClasses,
            oLang = oSettings.oLanguage.oPaginate,
            that = this;
 
        var iShowPages = oSettings.oInit.iShowPages || this.oDefaults.iShowPages,
            iShowPagesHalf = Math.floor(iShowPages / 2);
 
        $.extend(oSettings, {
            _iShowPages: iShowPages,
            _iShowPagesHalf: iShowPagesHalf
        });
 
        var oFirst = $('<a class="btn btn-small paging_first">&lArr;</a>'),
            oPrevious = $('<a class="btn btn-small paging_prev">&larr;</a>'),
            oNumbers = $('<span class="paging_num"></span>'),
            oNext = $('<a class="btn btn-small paging_next">&rarr;</a>'),
            oLast = $('<a class="btn btn-small paging_last">&rArr;</a>');
 
        oFirst.click({ 'fnCallbackDraw': fnCallbackDraw, 'oSettings': oSettings, 'sPage': 'first' }, that.fnClickHandler);
        oPrevious.click({ 'fnCallbackDraw': fnCallbackDraw, 'oSettings': oSettings, 'sPage': 'previous' }, that.fnClickHandler);
        oNext.click({ 'fnCallbackDraw': fnCallbackDraw, 'oSettings': oSettings, 'sPage': 'next' }, that.fnClickHandler);
        oLast.click({ 'fnCallbackDraw': fnCallbackDraw, 'oSettings': oSettings, 'sPage': 'last' }, that.fnClickHandler);
 
        // Draw
        $(nPager).append(oFirst, oPrevious, oNumbers, oNext, oLast);
    },
    // fnUpdate is only called once while table is rendered
    'fnUpdate': function(oSettings, fnCallbackDraw) {
        var oClasses = oSettings.oClasses,
            that = this;
 
        var tableWrapper = oSettings.nTableWrapper;
 
        // Update stateful properties
        this.fnUpdateState(oSettings);

	var totalPages = Math.ceil(oSettings._iRecordsDisplay / oSettings._iDisplayLength);
 
        if (oSettings._iCurrentPage === 1) {
            $('.paging_first', tableWrapper).attr('disabled', true);
            $('.paging_prev', tableWrapper).attr('disabled', true);
        } else {
            $('.paging_first', tableWrapper).removeAttr('disabled');
            $('.paging_prev', tableWrapper).removeAttr('disabled');
        }
 
        if (totalPages === 0 || oSettings._iCurrentPage === totalPages) {
            $('.paging_next', tableWrapper).attr('disabled', true);
            $('.paging_last', tableWrapper).attr('disabled', true);
        } else {
            $('.paging_next', tableWrapper).removeAttr('disabled');
            $('.paging_last', tableWrapper).removeAttr('disabled');
        }
 
        var i, oNumber, oNumbers = $('.paging_num', tableWrapper);

	var lastPage = totalPages < oSettings._iLastPage ? totalPages : oSettings._iLastPage;
 
        // Erase
        oNumbers.html('');
 
        for (i = oSettings._iFirstPage; i <= lastPage; i++) {
            oNumber = $('<a class="btn btn-small">' + oSettings.fnFormatNumber(i) + '</a>');
 
            if (oSettings._iCurrentPage === i) {
                oNumber.attr('active', true).attr('disabled', true).addClass('btn-primary');
            } else {
                oNumber.click({ 'fnCallbackDraw': fnCallbackDraw, 'oSettings': oSettings, 'sPage': i - 1 }, that.fnClickHandler);
            }
 
            // Draw
            oNumbers.append(oNumber);
        }
 
        // Add ellipses
        if (1 < oSettings._iFirstPage) {
            oNumbers.prepend('<span class="' + oClasses.sPageEllipsis + '">...</span>');
        }
 
        if (oSettings._iLastPage < totalPages) {
            oNumbers.append('<span class="' + oClasses.sPageEllipsis + '">...</span>');
        }
    },
    // fnUpdateState used to be part of fnUpdate
    // The reason for moving is so we can access current state info before fnUpdate is called
    'fnUpdateState': function(oSettings) {
        var iCurrentPage = Math.ceil((oSettings._iDisplayStart + 1) / oSettings._iDisplayLength),
            iTotalPages = Math.ceil(oSettings.fnRecordsTotal() / oSettings._iDisplayLength),
            iFirstPage = iCurrentPage - oSettings._iShowPagesHalf,
            iLastPage = iCurrentPage + oSettings._iShowPagesHalf;
 
        if (iTotalPages < oSettings._iShowPages) {
            iFirstPage = 1;
            iLastPage = iTotalPages;
        } else if (iFirstPage < 1) {
            iFirstPage = 1;
            iLastPage = oSettings._iShowPages;
        } else if (iLastPage > iTotalPages) {
            iFirstPage = (iTotalPages - oSettings._iShowPages) + 1;
            iLastPage = iTotalPages;
        }
 
        $.extend(oSettings, {
            _iCurrentPage: iCurrentPage,
            _iTotalPages: iTotalPages,
            _iFirstPage: iFirstPage,
            _iLastPage: iLastPage
        });
    }
};
