var timelineMinDate = new Date('1970-01-01 00:00:00');
var timelineMaxDate = new Date('2038-01-19 03:14:07');

function initBillingMappingsTimeline(divId,ajaxUrl,containerUpdateCb,locale,nowStr) {
    var ajaxSettings = $.extend( true, {}, $.ajaxSettings );
    ajaxSettings.crossDomain = false;
    ajaxSettings.timeout = 15000; //5000;
    ajaxSettings.type = "POST";
    ajaxSettings.async = true;
    ajaxSettings.dataType = 'json';
    ajaxSettings.contentType = "application/json; charset=utf-8",
    ajaxSettings.cache = true;
    ajaxSettings.global = false;
    ajaxSettings.error = null;
    ajaxSettings.beforeSend = function(jqXHR, settings) {
        //jqXHR.setRequestHeader('Connection', 'close');
    };
    ajaxSettings.complete = function(jqXHR, textStatus) {

    };
    //console.log(nowStr);
    var now = new Date(nowStr);
    now.setTime(now.getTime() + (new Date()).getTimezoneOffset() * 60000)
    var nearPast = new Date(new Date().setDate(now.getDate()-5));
    var nearFuture = new Date(new Date().setDate(now.getDate()+5));
    var options = {
        style: "range", //"box", "dot"
        showCurrentTime: true,
        showCustomTime: false,
        eventMargin: 10,
        height: "auto", //"300px",
        minHeight: 0, //200px
        width: "100%",
        "box.align": "center",
        showButtonNew: false,
        showNavigation: true,

        start: nearPast,
        end: nearFuture,
        min: null,
        max: null,
        scale: links.Timeline.StepDate.SCALE.DAY, //step
        showMajorLabels: true,
        showMinorLabels: true,
        axisOnTop: false,
        locale: locale,
        eventMarginAxis: 10,

        cluster: false,
        clusterMaxItems: 5,

        groupsChangeable: false,
        groupsOnRight: false,
        //groupsOrder: function(a, b) {},
        groupsWidth: null, //200px
        groupMinHeight: 0,

        zoomable: true,
        animateZoom: true,
        zoomMax: 315360000000000, //msecs
        zoomMin: 10, //msecs

        moveable: true,
        animate: true,
        dragAreaWidth: 10,
        editable: false,
        selectable: false,
        unselectable: true,
        timeChangeable: false,
        snapEvents: false,
        stackEvents: true,
        //customStackOrder: function(a, b) { //console.log(a); return b.i - a.i; }
    };
    var timeline = new links.Timeline(document.getElementById(divId), options);
    timeline.setCurrentTime(now);

    function getHeight() {
        return $("#" + divId + " div:first-child").height();
    }

    var initialized = false;
    function load(start,end) { //hoist
        //console.log(['load',start,end]);
        $.ajax($.extend( true, ajaxSettings, {
            url: ajaxUrl,
            data: JSON.stringify({
                start: (start != null ? start.toISOString() : null),
                end: (end != null ? end.toISOString() : null)
            }),
            context: this,
            success: function(data) {
                //console.log(data);
                var events = [];
                var contractCreate = new Date(data.timeline_data.contract.create_timestamp);
                for (var i = 0; i < data.timeline_data.events.length; i++) {
                    var event = data.timeline_data.events[i];
                    events.push({
                        'start': (event.start_date != null ? new Date(event.start_date) : contractCreate),
                        'end': (event.end_date != null ? new Date(event.end_date) : timelineMaxDate),
                        'content': event.billing_profile.name + (event.network.name != null ? '<br/>' + event.network.name : ''),
                        // Optional: a field 'group'
                        // Optional: a field 'className'
                        // Optional: a field 'editable'
                    });
                }
                var oldHeight = getHeight();
                timeline.draw(events);
                if (!initialized) {
                    timeline.setVisibleChartRange(nearPast, nearFuture);
                    initialized = true;
                }
                //console.log(events);
                if (typeof containerUpdateCb === 'function') {
                    containerUpdateCb(getHeight() - oldHeight);
                }
            }
        }));
    }

    links.events.addListener(timeline, 'rangechanged', function(eventData) {
        if (eventData != null) {
            load(eventData.start,eventData.end);
        }
    });
    //links.events.addListener(timeline, 'timechanged', function(eventData) {
    //    //console.log(['timechanged',eventData.time]);
    //    todo: use the custom time-bar to probe a billing mapping active at
    //          the given point in time.
    //});
    return {
        //Timeline: timeline,
        load: function() {
            var range = timeline.getVisibleChartRange();
            load(range.start,range.end);
        }
    };
}
