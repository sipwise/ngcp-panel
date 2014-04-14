/*
 * RRD graphing libraries, based on Flot
 * Part of the javascriptRRD package
 * Copyright (c) 2010 Frank Wuerthwein, fkw@ucsd.edu
 *                    Igor Sfiligoi, isfiligoi@ucsd.edu
 *
 * Original repository: http://javascriptrrd.sourceforge.net/
 * 
 * MIT License [http://www.opensource.org/licenses/mit-license.php]
 *
 */

/*
 *
 * Flot is a javascript plotting library developed and maintained by
 * Ole Laursen [http://code.google.com/p/flot/]
 *
 */

function suffixFormatter(val, axis) {
	var tickDec = 2;
	if (val > 1000000000)
		return (val / 1000000000).toFixed(tickDec) + "G";
	else if (val > 1000000)
		return (val / 1000000).toFixed(tickDec) + "M";
	else if (val > 1000)
		return (val / 1000).toFixed(tickDec) + "k";
	else
		return val.toFixed(tickDec);
}

function rrdFlot(html_id, rrd_file, graph_options, ds_graph_options, si_suffix, tz_offset) {
  if(si_suffix==null)
    this.si_suffix = false;
  else
    this.si_suffix = si_suffix;

  // tz_offset: offset of timezone in seconds
  if(tz_offset==null)
    this.tz_offset = 0;
  else
    this.tz_offset = tz_offset;

  this.html_id=html_id;
  this.rrd_file=rrd_file;
  this.graph_options=graph_options;
  if (ds_graph_options==null) {
    this.ds_graph_options=new Object();
  } else {
    this.ds_graph_options=ds_graph_options;
  }
  this.selection_range=new rrdFlotSelection();

  this.createHTML();
  this.populateRes();
  this.populateDScb();
  this.drawFlotGraph();
}


rrdFlot.prototype.createHTML = function() {
  var rf_this=this; // use obj inside other functions

  var base_el=document.getElementById(this.html_id);

  this.res_id=this.html_id+"_res";
  this.ds_cb_id=this.html_id+"_ds_cb";
  this.graph_id=this.html_id+"_graph";
  this.scale_id=this.html_id+"_scale";
  this.legend_sel_id=this.html_id+"_legend_sel";

  while (base_el.lastChild!=null) base_el.removeChild(base_el.lastChild);
  var external_table=document.createElement("Table");

  var rowHeader=external_table.insertRow(-1);
  var cellRes=rowHeader.insertCell(-1);
  var forRes=document.createElement("Select");
  forRes.id=this.res_id;
  forRes.onChange= this.callback_res_changed;
  forRes.onchange= function () {rf_this.callback_res_changed();};
  cellRes.appendChild(forRes);

  var cellScaleReset=rowHeader.insertCell(-1);
  cellScaleReset.vAlign="center";
  cellScaleReset.appendChild(document.createTextNode(" "));
  var elScaleReset=document.createElement("input");
  elScaleReset.type = "button";
  elScaleReset.value = "Reset Zoom";
  elScaleReset.setAttribute("class", "btn btn-tertiary btn-medium");
  elScaleReset.onclick = function () {rf_this.callback_scale_reset();}
  cellScaleReset.appendChild(elScaleReset);

  var rowGraph=external_table.insertRow(-1);
  var cellGraph=rowGraph.insertCell(-1);
  cellGraph.colSpan=3;
  var elGraph=document.createElement("Div");
  elGraph.style.width="670px";
  elGraph.style.height="200px";
  elGraph.id=this.graph_id;
  cellGraph.appendChild(elGraph);

  var cellDScb=rowGraph.insertCell(-1);
  cellDScb.vAlign="top";
  var formDScb=document.createElement("Form");
  formDScb.id=this.ds_cb_id;
  formDScb.onchange= function () {rf_this.callback_ds_cb_changed();};
  cellDScb.appendChild(formDScb);

  var rowScale=external_table.insertRow(-1);
  var cellScale=rowScale.insertCell(-1);
  cellScale.colSpan=2;
  var elScale=document.createElement("Div");
  elScale.style.width="670px";
  elScale.style.height="80px";
  elScale.id=this.scale_id;
  cellScale.appendChild(elScale);
 
  base_el.appendChild(external_table);
};

rrdFlot.prototype.populateRes = function() {
  var form_el=document.getElementById(this.res_id);

  while (form_el.lastChild!=null) form_el.removeChild(form_el.lastChild);

  var nrRRAs=this.rrd_file.getNrRRAs();
  for (var i=0; i<nrRRAs; i++) {
    var rra=this.rrd_file.getRRAInfo(i);
    if(rra.getCFName() != "AVERAGE")
        continue;
    var step=rra.getStep();
    var rows=rra.getNrRows();
    var period=step*rows;
    var rra_label=rfs_format_time(period) + " - " + rfs_format_time(step) + " steps";
    form_el.appendChild(new Option(rra_label,i));
  }
};

rrdFlot.prototype.populateDScb = function() {
  var form_el=document.getElementById(this.ds_cb_id);

  while (form_el.lastChild!=null) form_el.removeChild(form_el.lastChild);

  var nrDSs=this.rrd_file.getNrDSs();
  for (var i=0; i<nrDSs; i++) {
    var ds=this.rrd_file.getDS(i);
    var name=ds.getName();
    var title=name;
    var checked=1;
    if (this.ds_graph_options[name]!=null) {
      var dgo=this.ds_graph_options[name];
      if (dgo['title']!=null) {
	title=dgo['title'];
      } else if (dgo['label']!=null) {
	title=dgo['label'];
      }
      if (dgo['checked']!=null) {
	checked=dgo['checked'];
      }
    }
  }
};

// ======================================
// 
rrdFlot.prototype.drawFlotGraph = function() {
  var oSelect=document.getElementById(this.res_id);
  var rra_idx=Number(oSelect.options[oSelect.selectedIndex].value);

  var ds_positive_stack_list=[];
  var ds_negative_stack_list=[];
  var ds_single_list=[];
  var ds_colors={};

  var nrDSs=this.rrd_file.getNrDSs();
  for (var i=0; i<nrDSs; i++) {
	var ds_name=this.rrd_file.getDS(i).getName();
	var ds_stack_type='none';
	if (this.ds_graph_options[ds_name]!=null) {
	  var dgo=this.ds_graph_options[ds_name];
	  if (dgo['stack']!=null) {
	    var ds_stack_type=dgo['stack'];
	  }
	}
	if (ds_stack_type=='positive') {
	  ds_positive_stack_list.push(ds_name);
	} else if (ds_stack_type=='negative') {
	  ds_negative_stack_list.push(ds_name);
	} else {
	  ds_single_list.push(ds_name);
	}
	ds_colors[ds_name]=i;
  } 
  
  var flot_obj=rrdRRAStackFlotObj(this.rrd_file,rra_idx,
    ds_positive_stack_list,ds_negative_stack_list,ds_single_list,
    this.tz_offset);

  for (var i=0; i<flot_obj.data.length; i++) {
    var name=flot_obj.data[i].label;
    var color=ds_colors[name];
    if (this.ds_graph_options[name]!=null) {
      var dgo=this.ds_graph_options[name];
      if (dgo['color']!=null) {
	color=dgo['color'];
      }
      if (dgo['label']!=null) {
	flot_obj.data[i].label=dgo['label'];
      } else  if (dgo['title']!=null) {
	flot_obj.data[i].label=dgo['title'];
      }
      if (dgo['lines']!=null) {
	flot_obj.data[i].lines=dgo['lines'];
      }
      if (dgo['yaxis']!=null) {
	flot_obj.data[i].yaxis=dgo['yaxis'];
      }
    }
    flot_obj.data[i].color=color;
  }

  this.bindFlotGraph(flot_obj);
};

rrdFlot.prototype.bindFlotGraph = function(flot_obj) {
  var rf_this=this;

  var graph_jq_id="#"+this.graph_id;
  var scale_jq_id="#"+this.scale_id;
  fmt_cb = this.si_suffix ? suffixFormatter : null;

  var graph_options = {
    legend: {show:false, position:"nw",noColumns:5, backgroundOpacity: 0.5 },
    lines: {show:true},
    xaxis: { mode: "time" },
    yaxis: { autoscaleMargin: 0.20, tickFormatter: fmt_cb },
    selection: { mode: "x" },
  };

  graph_options.legend.show=true;

  if (this.selection_range.isSet()) {
    var selection_range=this.selection_range.getFlotRanges();
    graph_options.xaxis.min=selection_range.xaxis.from;
    graph_options.xaxis.max=selection_range.xaxis.to;
  } else {
    graph_options.xaxis.min=flot_obj.min;
    graph_options.xaxis.max=flot_obj.max;
  }

  if (this.graph_options!=null) {
    if (this.graph_options.legend!=null) {
      if (this.graph_options.legend.position!=null) {
	graph_options.legend.position=this.graph_options.legend.position;
      }
      if (this.graph_options.legend.noColumns!=null) {
	graph_options.legend.noColumns=this.graph_options.legend.noColumns;
      }
    }
    if (this.graph_options.yaxis!=null) {
      if (this.graph_options.yaxis.autoscaleMargin!=null) {
	graph_options.yaxis.autoscaleMargin=this.graph_options.yaxis.autoscaleMargin;
      }
    }
    if (this.graph_options.lines!=null) {
      graph_options.lines=this.graph_options.lines;
    }
  }

  var scale_options = {
    legend: {show:false},
    lines: {show:true},
    xaxis: { mode: "time", min:flot_obj.min, max:flot_obj.max },
    yaxis: { tickFormatter: fmt_cb },
    selection: { mode: "x" },
  };
    
  var flot_data=flot_obj.data;

  var graph_data=this.selection_range.trim_flot_data(flot_data);
  var scale_data=flot_data;

  this.graph = $.plot($(graph_jq_id), graph_data, graph_options);
  this.scale = $.plot($(scale_jq_id), scale_data, scale_options);

  if (this.selection_range.isSet()) {
    this.scale.setSelection(this.selection_range.getFlotRanges(),true);
  }

  $(graph_jq_id).unbind("plotselected"); 
  $(graph_jq_id).bind("plotselected", function (event, ranges) {
      rf_this.selection_range.setFromFlotRanges(ranges);
      graph_options.xaxis.min=ranges.xaxis.from;
      graph_options.xaxis.max=ranges.xaxis.to;
      rf_this.graph = $.plot($(graph_jq_id), rf_this.selection_range.trim_flot_data(flot_data), graph_options);
      
      rf_this.scale.setSelection(ranges, true);
  });
   
  $(scale_jq_id).unbind("plotselected");
  $(scale_jq_id).bind("plotselected", function (event, ranges) {
      rf_this.graph.setSelection(ranges);
  });

  $(scale_jq_id).bind("plotunselected", function() {
      rf_this.selection_range.reset();
      graph_options.xaxis.min=flot_obj.min;
      graph_options.xaxis.max=flot_obj.max;
      rf_this.graph = $.plot($(graph_jq_id), rf_this.selection_range.trim_flot_data(flot_data), graph_options);
  });
};

rrdFlot.prototype.callback_res_changed = function() {
  this.drawFlotGraph();
};

rrdFlot.prototype.callback_ds_cb_changed = function() {
  this.drawFlotGraph();
};

rrdFlot.prototype.callback_scale_reset = function() {
  this.scale.clearSelection();
};

rrdFlot.prototype.callback_legend_changed = function() {
  this.drawFlotGraph();
};

