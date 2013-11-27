var chord;
function loadChord() {

$("#ngcp-cdr-chord-loading").remove();
$("#ngcp-cdr-chord").append(
    '<div id="ngcp-cdr-chord-loading" style="margin-top:30px">' +
    '  <img src="/img/loader.gif" alt="loading" style="margin-right: 10px;"/>' +
    '  <span><i>crunching data, please be patient - it might take a while...</i></span>' +
    '</div>'
);

$.ajax({
    url: "/calls/ajax?from=" + $("#datepicker_start").val() + "&to=" + $("#datepicker_end").val(),
    type: "get",
    async: true,
    datatype: "json",
    error: function(xhr, textStatus, errorThrown) {
        $("#ngcp-cdr-chord-loading").remove();
        $("#ngcp-cdr-chord").append('<div id="ngcp-cdr-chord-loading">Failed to load call data</div>');
    },
    success: function(resjson, textStatus, XMLHttpRequest) {
        $("#ngcp-cdr-chord-loading").remove();
        var json = $.parseJSON(resjson);
    	var countries = json.countries;
	    var matrix = json.calls;

        if(matrix.length == 0) {
            $("#ngcp-cdr-chord").append('<div id="ngcp-cdr-chord-loading">No call data for the specified date range found</div>');
            return;
        }


        var width = 720,
            height = 720,
            outerRadius = Math.min(width, height) / 2 - 10,
            innerRadius = outerRadius - 24;

        //var formatPercent = d3.format(".1%");
        var formatPercent = function(v) {
          return Math.floor(v);
        };

        var arc = d3.svg.arc()
            .innerRadius(innerRadius)
            .outerRadius(outerRadius);

        var layout = d3.layout.chord()
            .padding(.04)
            .sortSubgroups(d3.descending)
            .sortChords(d3.ascending);

        var path = d3.svg.chord()
            .radius(innerRadius);

        var svg = d3.select("#ngcp-cdr-chord").append("svg")
            .attr("width", width)
            .attr("height", height)
          .append("g")
            .attr("id", "circle")
            .attr("transform", "translate(" + width / 2 + "," + height / 2 + ")");

        svg.append("circle")
            .attr("r", outerRadius);


        // Compute the chord layout.
        layout.matrix(matrix);

        // Add a group per neighborhood.
        var group = svg.selectAll(".group")
            .data(layout.groups)
            .enter().append("g")
            .attr("class", "group")
            .on("mouseover", mouseover);

        // Add a mouseover title.
        group.append("title").text(function(d, i) {
            return countries[i] + ": " + formatPercent(d.value) + " originating calls";
        });

        // Add the group arc.
        var fill = d3.scale.category10();
        var groupPath = group.append("path")
            .attr("id", function(d, i) { return "group" + i; })
            .attr("d", arc)
            .style("fill", function(d, i) { return fill(i); });

        // Add a text label.
        var groupText = group.append("text")
            .attr("x", 6)
            .attr("dy", 15);

        groupText.append("textPath")
            .attr("xlink:href", function(d, i) { return "#group" + i; })
            .text(function(d, i) { return countries[i]; });

        // Remove the labels that don't fit. :(
        groupText.filter(function(d, i) { return groupPath[0][i].getTotalLength() / 2 - 16 < this.getComputedTextLength(); })
            .remove();

        // Add the chords.
        chord = svg.selectAll(".chord")
            .data(layout.chords)
          .enter().append("path")
            .attr("class", "chord")
            .style("fill", function(d) { return fill(d.source.index); })
            .attr("d", path);

        // Add an elaborate mouseover title for each chord.
        chord.append("title").text(function(d) {
          return countries[d.source.index]
              + " → " + countries[d.target.index]
              + ": " + formatPercent(d.source.value)
              + "\n" + countries[d.target.index]
              + " → " + countries[d.source.index]
              + ": " + formatPercent(d.target.value);
        });
    }
});

}

function mouseover(d, i) {
  chord.classed("fade", function(p) {
    return p.source.index != i
        && p.target.index != i;
  });
}

/* vim: set tabstop=4 syntax=javascript expandtab: */
