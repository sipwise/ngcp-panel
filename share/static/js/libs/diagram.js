var colors=["green", "red", "sienna", "orange", "black", "purple", "chocolate", "olivedrab", "darkred", "darkslategrey", "midnightblue", "maroon", "teal", "goldenrod", "gray", "darkolivegreen", "darkcyan", "brown", "peru", "mediumorchild", "navy", "saddlebrown", "coral"];

function line_color(d)
{
    return colors[d];
}

var aliases = { };

function classToAlias(c)
{
    var alias = aliases[c];

    if (alias == undefined)
    {
        alias = c;
    }

    return alias;
}

function receiver(d, considerports)
{
    var rc = d.dst_ip;

    if (considerports)
    {
        rc += ":" + d.dst_port;
    }

    return classToAlias(rc);
}

function sender(d, considerports)
{
    var rc = d.src_ip;

    if (considerports)
    {
        rc += ":" + d.src_port;
    }

    return classToAlias(rc);
}

function prepareData(data, considerports)
{
    console.log("prepare data");

    data.frames.forEach(function(m, i) {
            m.hidden = false;
            m.drawable = true;
        });

        data.frames.forEach(function(m, i) {

        var i = (sender(m, considerports) == receiver(m, considerports))

        m.internal = i;
        m.drawable = !i;
    });

    return data;
}


function hostPortToClass(c)
{
    return "class-" + classToAlias(c).replace(/\./g, "_").replace(":", "_");
}

function toggleSVG(node)
{
    console.log(node);
    var x = document.getElementsByClassName(node);

    console.log(x.length);
    var i; for (i = 0; i < x.length; i++)
    {
        x[i].style.display = (x[i].style.display == 'none') ? 'block' : 'none';
    }
}

function createSvg(container)
{
    var width = parseInt(d3.select(container).style("width"), 10);

    return d3.select(container).append("svg").attr("width", width );
}

function redraw(data, considerports)
{
    var svg = d3.selectAll("svg");
    svg.remove();
    draw_sequence_diagram(data, considerports);
}

function hidePackets(rawdata, pattern, considerports)
{
    console.log("hide packets", pattern);

    rawdata.frames.forEach(function(item, i)
    {
        if (sender(item, considerports) == pattern || receiver(item, considerports) == pattern)
        {
            item.hidden = !item.hidden;
        }
    });

    redraw(rawdata, considerports);
}

function hideInternalPackets(rawdata, considerports)
{
    console.log("hide internal");

    rawdata.frames.forEach(function(item, i) {
        if (item.internal)
        {
            item.drawable = !item.drawable;
        }
    });

    redraw(rawdata, considerports);
}

function getNodes(data, considerports)
{
    var senders = d3.set(data.map(function(d){ return sender(d, considerports); })).values();
    var receivers = d3.set(data.map(function(d){ return receiver(d, considerports); })).values();
    return _.union(senders, receivers);
}

function considerPortsClick(rawdata, considerports)
{
    console.log("consider ports click");
    prepareData(rawdata, !considerports);
    redraw(rawdata, !considerports);
}

function draw_sequence_diagram(rawdata, considerports)
{
    var chartName = rawdata.call;
    var data = rawdata.frames;

    function considerPorts()
    {
        considerPortsClick(rawdata, considerports);
    }

    function hideInternal()
    {
        hideInternalPackets(rawdata, considerports);
    }

    var message_frame = d3.select("#message-frame");

    function showMessageBody(m)
    {
       message_frame.html("<textarea>" + "packet# " + m.id + "\n" + m.payload + "</textarea>");
    }

    function listClasses(m, considerports)
    {
        return hostPortToClass(sender(m, considerports)) + " " +
               hostPortToClass(receiver(m, considerports)) + " " +
               "class-message";
    }

    function classClick(node)
    {
        console.log("class click", node);

        // FIXME reimplement with d3
        // toggleSVG(hostPortToClass(node));
        hidePackets(rawdata, node, considerports);

    }

    function initAliases(nodes)
    {
        if (_.isEmpty(aliases))
        {
            var nodes1 = nodes.slice();

            if (typeof preAliases !== 'undefined')
            {
                for (var key in preAliases)
                {
                    var index = nodes1.indexOf(key);
                   if (index != -1)
                   {
                       nodes1[index] = preAliases[key]; 
                   }
                }
            }

            dictedit.init("nodeEditor", null, nodes, nodes1);
            aliases = dictedit.value("nodeEditor");
            applyNodeEdit();
        }
    }

    var button = d3.select("#hideInternalButton").on("click", hideInternal);
    var button1 = d3.select("#considerPortsButton").on("click", considerPorts);
    var expand = d3.select("#expandEditor").on("click", expandEditor);
    var apply = d3.select("#applyNodeEdit").on("click", applyNodeEdit);

    function applyNodeEdit() {
        aliases = dictedit.value("nodeEditor");
        redraw(rawdata, considerports);
    };

    function expandEditor() {
        $("#editorDiv").slideToggle(200);
    };

    var header = createSvg("#diagram_header");
    var svg = createSvg("#diagram");

    var margin = { top: 20, right: 20, bottom: 20, left: 20 },
        width = +svg.attr('width') - margin.left - margin.right,
        height = +svg.attr('height') - margin.top - margin.bottom,
        g = header.append('g').attr('transform', 'translate(' + margin.left + ',' + margin.top + ')');

     // Graph title
     g.append('text')
        .attr('x', (width / 2))
        .attr('y', 0 - (margin.top / 4))
        .attr('class', 'class-title')
        .text(chartName);

     var nodes = getNodes(data, considerports);

     initAliases(nodes);

     var XPAD = 200; // horizontal padding for vertical lines/messages/labels
     var YPAD = 20;
     var VERT_SPACE = parseInt(width/nodes.length);

     var MESSAGE_SPACE = 30;
     svg.attr("height", (data.length+2)*MESSAGE_SPACE);

     var MESSAGE_LABEL_X_OFFSET = -50;
     var MESSAGE_LABEL_Y_OFFSET = 10;
     var MESSAGE_ARROW_Y_OFFSET = 15;

     var CLASS_WIDTH = 150;
     var CLASS_LABEL_X_OFFSET = -30;
     var CLASS_LABEL_Y_OFFSET = 25;

     // Draw vertical lines
     nodes.forEach(function(c, i) {
          var line = svg.append("line")
          .attr("class", "class-vertical-line")
          .attr("x1", XPAD + i * VERT_SPACE)
          .attr("y1", 0) // YPAD + MESSAGE_SPACE)
          .attr("x2", XPAD + i * VERT_SPACE)
          .attr("y2", YPAD + data.length * (MESSAGE_SPACE + 5))
     });

     // Draw class labels
     nodes.forEach(function(c, i) {
        var x = XPAD + i * VERT_SPACE;
        var g1 = header.append("g")
          .attr("transform", "translate(" + x + "," + YPAD + ")")
          .attr("class", "class-rect")
          .append("rect")
          .attr("x", -CLASS_WIDTH/2)
          .attr("y", "0")
          .attr("width", CLASS_WIDTH)
          .attr("height", "24px")
          .on("click", function() { classClick(c) })

        var g2 = header.append("g")
          .attr("transform", "translate(" + x + "," + YPAD + ")")
          .append("text")
          .attr("class", "class-label")
          .attr("text-anchor", "middle")
          .text(function (d) { return classToAlias(c); })
          .attr("dy", "16px")
          .on("click", function() { classClick(c) })
      });

      var i = -1;
      var message_number = 0;

      data.forEach(function(m, c) {

      // FIXME var lcolor = line_color(m.session_id);
      var lcolor = line_color(0);
      var tcolor = "black";

      if (!m.drawable)
      {
          return;
      }

      i++;

      if (m.hidden)
      {
          lcolor = "lightgrey";
          tcolor = "lightgrey";
      }

      // draw packet number
      var xPos = 0;
      var yPos = MESSAGE_LABEL_Y_OFFSET + i * MESSAGE_SPACE;
      var classes = listClasses(m, considerports);

      var g1 = svg.append("g")
          .attr("transform", "translate(" + xPos + "," + yPos + ")")
          .attr("text-anchor", "left")
          .attr("class", classes)
          .attr("class", "message-number")
          .append("text")
          .style("fill", tcolor)
          .text(message_number++);


      // draw timestamp
      var xPos = XPAD/2;
      var yPos = MESSAGE_LABEL_Y_OFFSET + i * MESSAGE_SPACE;

      g1 = svg.append("g")
          .attr("transform", "translate(" + xPos + "," + yPos + ")")
          .attr("text-anchor", "middle")
          .attr("class", classes)
          .append("text")
          .style("fill", tcolor)
          .style("font-size", "10px")
          .text(m.timestamp);

      // draw message labels
      xPos = XPAD + MESSAGE_LABEL_X_OFFSET + (((nodes.indexOf(receiver(m, considerports)) - nodes.indexOf(sender(m, considerports))) * VERT_SPACE) / 2) + (nodes.indexOf(sender(m, considerports))  * VERT_SPACE);
      yPos = MESSAGE_LABEL_Y_OFFSET + i * MESSAGE_SPACE;

      // draw message labels
      g1 = svg.append("g")
          .attr("transform", "translate(" + xPos + "," + yPos + ")")
          .append("text")
          .attr("dx", "5px")
          .attr("dy", "-2px")
          .attr("text-anchor", "begin")
          .style("fill", tcolor)
          .attr("class", classes)
          .on("click", function() { showMessageBody(m) })
          .text(m.cseq_method + " " + m.request_uri);

      // draw line
      var y = MESSAGE_ARROW_Y_OFFSET + (i) * MESSAGE_SPACE;
      var line = svg.append("line")
          .style("stroke", lcolor)
          .attr("x1", XPAD + nodes.indexOf(sender(m, considerports)) * VERT_SPACE)
          .attr("y1", y)
          .attr("x2", XPAD + nodes.indexOf(receiver(m, considerports)) * VERT_SPACE)
          .attr("y2", y)
          .attr("marker-end", "url(#end)")
          .on("click", function() { showMessageBody(m) })

          if (m.hidden)
          {
            line.attr("marker-end", "url(#hidden)");
          }
          else
          {
            line.attr("marker-end", "url(#end)");
          }
      });

      // Arrow style
      svg.append("svg:defs").selectAll("marker")
          .data(["end"])
        .enter().append("svg:marker")
          .attr("id", String)
          .attr("viewBox", "0 -5 10 10")
          .attr("refX", 10)
          .attr("refY", 0)
          .attr("markerWidth", 10)
          .attr("markerHeight", 10)
          .attr("orient", "auto")
          .attr("fill", "blue")
        .append("svg:path")
          .style("stroke", "blue")
          .attr("d", "M0,-3L10,0L0,3");

      // Arrow style
      svg.append("svg:defs").selectAll("marker")
          .data(["hidden"])
        .enter().append("svg:marker")
          .attr("id", String)
          .attr("viewBox", "0 -5 10 10")
          .attr("refX", 10)
          .attr("refY", 0)
          .attr("markerWidth", 10)
          .attr("markerHeight", 10)
          .attr("orient", "auto")
          .attr("fill", "lightgrey")
        .append("svg:path")
          .style("stroke", "lightgrey")
          .attr("d", "M0,-3L10,0L0,3");

    showMessageBody(data[0]);
}
