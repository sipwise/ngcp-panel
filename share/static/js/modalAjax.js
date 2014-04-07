function refreshAjaxList ( item, data ){
    //alert('refreshAjaxList: q='+uriForAction( data, item + '_list' )+';item='+item);
    var target = $('#'+ item + '_list');
    if(target){
        fetch_into(
            item + '_list',
            uriForAction( data, item + '_list' ),
            '',
            function(){ 
                mainWrapperInit();
                listRestoreCurrentEdit(target);
            }
        );
    }
}
function refreshMessagesAjax (  ){
    //alert('refreshMessagesAjax: q='+uriForAction( {}, 'messages' ));
    fetch_into(
        'messages',
        uriForAction( {}, 'messages' )
    );
}
function processModalFormAjax( form, callback ) {
    //preventDefault();
    //alert(form.attr('action')+'?'+form.serialize());
    var item = form.attr('id');
    $.ajax( {
        url: form.attr('action'),
        type: "POST",
        data: form.serialize(),
    } ).done( function( responseText, textStatus, request ) {
        /*
        var headers = request.getAllResponseHeaders();
        var i =0;
        alert('headers='+headers);
        for(i=0; i<headers.length; i++){
            alert('i='+i+';header='+headers[i]);
        }
        */
        var status = request.getResponseHeader('X-Form-Status');
        //alert('header='+request.getResponseHeader('X-Form-Status'));
        var targetNames = [ item + '_messages','messages' ];
        if('error' == status){
            targetNames.unshift(item+'_form');
        }
/*
        if(var targetDirect = request.getResponseHeader('X-Ajax-Target')){
            targetNames.unshift(targetDirect);
        }
*/
        
        var target,i=0;
        while( (!target) && ( i < targetNames.length ) ){
            target = document.getElementById(targetNames[i++]);
            //alert('i='+(i-1)+';name='+targetNames[i-1]+';target='+target);
        }
        //alert('target='+target);
        if(target){
            target.innerHTML=responseText;
        }
        if(callback){
            if(typeof callback == 'function'){
				callback(status,form);
			}else{
				eval(callback);
			}
        }
    });
}
function listRestoreCurrentEdit(staticContainer, staticContainerId){
    if(!staticContainer){
        staticContainer = $('#'+ staticContainerId );
    }
    if(staticContainer){
        var id = getCurrentEditId(staticContainer, staticContainerId);
        //alert('listRestoreCurrentEdit:id='+id+';');
        if(id){
            var tr = staticContainer.find('tr[data-id='+id+']');
            if(tr){
                listSetCurrentEdit( id, tr, staticContainer );
            }
        }
    }
}
function getCurrentEditId(staticContainer, staticContainerId){
    var res = '';
    if(!staticContainer){
        staticContainer = $('#'+ staticContainerId );
    }
    if(staticContainer){
        res = staticContainer.attr('data-current');
    }
    return res;
}
function setCurrentEditId(id, staticContainer, staticContainerId){
    if(!staticContainer){
        staticContainer = $('#'+ staticContainerId );
    }
    if(staticContainer){
        staticContainer.attr('data-current',id);
    }
}
function listSetCurrentEdit( id, tr, staticContainer ) {
    //alert('listSetCurrentEdit: id='+id+';tr='+tr+';');
    var curclass = 'ngcp_current_edit';
    if(!staticContainer){
        staticContainer = tr.closest('.accordion-inner');
    }
    if(staticContainer){
        setCurrentEditId(id, staticContainer);
        staticContainer.find('.'+curclass ).each( function(i){
             $(this).removeClass(curclass);
        } );
    }
    //tr.find('td').addClass('ngcp_current_edit');
    if(tr){
        tr.addClass(curclass);
        //alert('listSetCurrentEdit: class='+id+';tr='+tr.attr('class')+';');
    }
    /*else{
        //tr.find('td').removeClass('ngcp_current_edit');
        tr.removeClass(curclass);
    }*/
}