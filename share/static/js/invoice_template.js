//constructor
var svgCanvasEmbed = null;
function init_embed() {
    var svgEditFrameName = 'svgedit';
    var frame = document.getElementById(svgEditFrameName);
    svgCanvasEmbed = new EmbeddedSVGEdit(frame);
    // Hide main button, as we will be controlling new/load/save etc from the host document
    var doc = frame.contentDocument;
    if (!doc)
    {
        doc = frame.contentWindow.document;
    }
    var mainButton = doc.getElementById('main_button');
    mainButton.style.display = 'none';
}
//private
function getSvgString(){
    return svgCanvasEmbed.frame.contentWindow.svgCanvas.getSvgString();
}
function setSvgStringToEditor( svgParsedString ){
    //alert('setSvgStringToEditor: '+svgParsedString);
    svgCanvasEmbed.setSvgString( svgParsedString )(
        function(data,error){
            if(error){
            }else{
                svgCanvasEmbed.zoomChanged('', 'canvas');
            }
        }
    );
}
function setSvgStringToPreview( svgParsedString, q, data ) {
    var previewIframe = document.getElementById('svgpreview'); 
    //alert('setSvgStringToPreview: svgParsedString='+svgParsedString+';');
    if ($.browser.msie) {
        //we need to repeat query to server for msie if we don't want send template string via GET method
        if(!q){
            var dataPreview = data;
            dataPreview.tt_viewmode = 'parsed';
            dataPreview.tt_type = 'svg';
            dataPreview.tt_sourcestate = dataPreview.tt_sourcestate || 'saved';
            q = uriForAction( dataPreview, 'invoice_template' );
        }
        previewIframe.src = q;
    }else{
        previewIframe.src = "data:text/html," + encodeURIComponent(svgParsedString);
    }
}
function fetchSvgToEditor( data ) {
    var q = uriForAction( data, 'invoice_template' );
    //alert('fetchSvgToEditor: q='+q+';');
    $.ajax({
        url: q,
    }).done( function ( httpResponse ){ 
        setSvgStringToEditor( httpResponse );
    });
}
//public
function fetchInvoiceTemplateData( data, noshowform ){
    //params spec: tt_type=[svg|html]/tt_viewmode[parsed|raw]/tt_sourcestate[saved|previewed|default]/tt_output_type[svg|pdf|html|json|svgzip|pdfzip|htmlzip]/tt_id
    //tt_output_type=svg really outputs text/html mimetype. But it will be couple of <svg> tags (<svg> per page).
    data.tt_output_type = 'json';
    var q = uriForAction( data, 'invoice_template' );
    alert('fetchInvoiceTemplateData: q='+q+';');
    $.ajax({
        url: q,
        datatype: "json",
    //}).done( function( jsonres ){
    }).done( function( templatedata ){
        //alert(templatedata);
        //alert(templatedata.aaData);
        if(templatedata.aaData){
            if( templatedata.aaData.template ){
                setSvgStringToEditor( templatedata.aaData.template.raw );
                setSvgStringToPreview( templatedata.aaData.template.parsed );
            }
            $('#load_previewed_control').css('display', 'none' );
            if( templatedata.aaData.form ){
                $('form[name=invoice_template_editor]').loadJSON(templatedata.aaData.form);
                if(templatedata.aaData.form.base64_previewed){
                    $('#load_previewed_control').css('display', 'inline' );
                }
            }
            if( !noshowform ){
                $('#invoice_template_editor_form').css('display','block');
            }
        }
    });
}
function clearTemplateForm(data){
    $('#invoice_template_editor_form').css('display','none');
    if(!data){
        data = {};
    }
    data.tt_sourcestate = 'default';
    fetchInvoiceTemplateData(data, 1);
}
function savePreviewedAndShowParsed( data ){
    var svgString = getSvgString();
    var q = uriForAction( data, 'invoice_template_previewed' ); 
    //alert('savePreviewedAndShowParsed: svgString='+svgString+'; q='+q+';');
    //alert('savePreviewedAndShowParsed: q='+q+';');
    //save 
    q=formToUri(q);
    $.post( q, { template: svgString } )
    .done( function( httpResponse ){
        // & show template
        //alert('savePreviewedAndShowParsed: httpResponse='+httpResponse+';');
        setSvgStringToPreview( httpResponse, q )
        //refresh list after saving
        refreshAjaxList( 'invoice_template', data );
    } );
}
function saveTemplate( data ) {	
    var svgString = getSvgString();
    data.tt_sourcestate='saved';
    data.tt_output_type = 'json';
    var q = uriForAction( data, 'invoice_template_saved' ); 
    q=formToUri(q);
    alert('saveTemplate: q='+q+';');
    $.ajax( {
        url: q,
        type: "POST",
        datatype: 'json',
        data: { template: svgString },
    } ).done( function( jsonResponse ) {
        if(jsonResponse.aaData && jsonResponse.aaData.form){
            $('form[name=invoice_template_editor]').loadJSON(jsonResponse.aaData.form);
        }
        refreshAjaxList( 'invoice_template', data );
    });
}
