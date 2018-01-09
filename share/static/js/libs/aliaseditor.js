var dictedit = {
  value: function(id){
    var res = {};
    var ta = document.getElementById(id);
    var rows = ta.value.split(ta.dataset["dictedit_delim"]);

    for (var i = 0; i < rows.length; i++) {
        var x = rows[i].split(ta.dataset["dictedit_sep"]);
        if (x[0] != "")
        {
            res[x[0]] = x[1];
        }
    }

    return res;
  },
  init: function(id, opts, initKeys, initValues) {
    opts = opts || {};
    var ta = document.getElementById(id);
    var newNode = document.createElement("div");
    newNode.id = id + "_dictedit" //+ new Date().getTime();
    newNode.className = "dictedit-wrapper " + id + "_dictedit";
    ta.parentNode.insertBefore(newNode,ta);
    ta.style.display = "none";
    var delim = opts.delim || ";";
    var sep = opts.sep || " : ";
    ta.dataset["dictedit_sep"] = sep;
    ta.dataset["dictedit_delim"] = delim;
    for(var i = 0; i < initKeys.length; i++){
      if (initKeys[i].length > 0){
        dictedit.addRow(id, initKeys[i], initValues[i]);
      }
    }
    dictedit.updateRows(id.split("_dictedit")[0]);
  },
  addRow: function(taID, a, b){
    var id = taID + "_dictedit";
    this.__handleRowAdd(id, a, b);
  },
  __handleKeyPress: function(e){
    var id = e.target.parentNode.id;
    var y = function(){
      dictedit.updateRows(id.split("_dictedit")[0]);
    }
    setTimeout(y, 100);
  },
  __handleRowAdd: function(id, a, b) {
    var taID = id.split("_dictedit")[0];
    var dataset = document.getElementById(taID).dataset;
    var sep = dataset.dictedit_sep || ": ";
    var delim = dataset.dictedit_delim || "; ";
    var temp = new Date().getTime().toString();
    var outS = "<input onkeydown='dictedit.__handleKeyPress(event)' class='" + temp + " left' value='" + a + "' readonly>"
        + "<input  onkeydown='dictedit.__handleKeyPress(event)' class='" + temp + " right' value='" + b + "'>" 
        + "<br class='" + temp + "'>";
    $("#" + id).append(outS);
  },
  updateRows(taID)
  {
    var id = taID + "_dictedit";
    var ret = "";
    var dataset = document.getElementById(taID).dataset;
    var sep = dataset.dictedit_sep || ": ";
    var delim = dataset.dictedit_delim || "; ";
    var list = document.getElementById(id).getElementsByTagName("input");
    for(var i = 0; i < list.length/2; i++){
      ret += list[i*2].value + sep +  list[i*2+1].value + delim;
    }
    document.getElementById(taID).value = ret;
    return ret;
  }
}
