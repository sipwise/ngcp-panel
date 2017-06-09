var timelineMinDate = new Date('1970-01-01 00:00:00');
var timelineMaxDate = new Date('2038-01-19 03:14:07');

function initBillingMappingsTimeline(divId,ajaxUrl,locale) {
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
    var now = new Date();
    var nearPast = new Date(new Date().setDate(now.getDate()-5));
    var nearFuture = new Date(new Date().setDate(now.getDate()+5));
    var options = {
        style: "range", //"box", "dot"
        showCurrentTime: true,
        showCustomTime: false,
        eventMargin: 10,
        height: "300px",
        minHeight: 0, //200px
        width: "100%",
        "box.align": "center",
        showButtonNew: false,
        showNavigation: false,

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
        customStackOrder: function(a, b) { return a.i - b.i; }
    };
    var timeline = new links.Timeline(document.getElementById(divId), options);

    var initialized = false;
    function load(start,end) { //hoist
        console.log(['load',start,end]);
        $.ajax($.extend( true, ajaxSettings, {
            url: ajaxUrl,
            data: JSON.stringify({
                start: (start != null ? start.toISOString() : null),
                end: (end != null ? end.toISOString() : null)
            }),
            context: this,
            success: function(data) {
                console.log(data);
                var events = [];
                for (var i = 0; i < data.timeline_data.events.length; i++) {
                    var event = data.timeline_data.events[i];
                    events.push({
                        'start': (event.start_date != null ? new Date(event.start_date) : new Date(data.timeline_data.contract.create_timestamp)),
                        'end': (event.end_date != null ? new Date(event.end_date) : timelineMaxDate),
                        'content': event.billing_profile.name,
                        'i': i,
                        // Optional: a field 'group'
                        // Optional: a field 'className'
                        // Optional: a field 'editable'
                    });
                }
                timeline.draw(events);
                if (!initialized) {
                    timeline.setVisibleChartRange(nearPast, nearFuture);
                    initialized = true;
                }
                console.log(events);
                //response.call(this, data);
                //timeline.draw([]);
            }
        }));
    }

    links.events.addListener(timeline, 'rangechanged', function(eventData) {
        if (eventData != null) {
            load(eventData.start,eventData.end);
        }
    });
    links.events.addListener(timeline, 'timechanged', function(eventData) {
        console.log(['timechanged',eventData.time]);
    });
    return {
        //Timeline: timeline,
        load: function() {
            var range = timeline.getVisibleChartRange();
            load(range.start,range.end);
        }
    };
}
