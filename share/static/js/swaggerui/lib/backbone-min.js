!function(t,e){if("function"==typeof define&&define.amd)define(["underscore","jquery","exports"],function(i,n,s){t.Backbone=e(t,s,i,n)});else if("undefined"!=typeof exports){var i=require("underscore");e(t,exports,i)}else t.Backbone=e(t,{},t._,t.jQuery||t.Zepto||t.ender||t.$)}(this,function(t,e,i,n){var s=t.Backbone,r=[],a=(r.push,r.slice);r.splice;e.VERSION="1.1.2",e.$=n,e.noConflict=function(){return t.Backbone=s,this},e.emulateHTTP=!1,e.emulateJSON=!1;var o=e.Events={on:function(t,e,i){if(!c(this,"on",t,[e,i])||!e)return this;this._events||(this._events={});var n=this._events[t]||(this._events[t]=[]);return n.push({callback:e,context:i,ctx:i||this}),this},once:function(t,e,n){if(!c(this,"once",t,[e,n])||!e)return this;var s=this,r=i.once(function(){s.off(t,r),e.apply(this,arguments)});return r._callback=e,this.on(t,r,n)},off:function(t,e,n){var s,r,a,o,h,u,l,d;if(!this._events||!c(this,"off",t,[e,n]))return this;if(!t&&!e&&!n)return this._events=void 0,this;for(o=t?[t]:i.keys(this._events),h=0,u=o.length;h<u;h++)if(t=o[h],a=this._events[t]){if(this._events[t]=s=[],e||n)for(l=0,d=a.length;l<d;l++)r=a[l],(e&&e!==r.callback&&e!==r.callback._callback||n&&n!==r.context)&&s.push(r);s.length||delete this._events[t]}return this},trigger:function(t){if(!this._events)return this;var e=a.call(arguments,1);if(!c(this,"trigger",t,e))return this;var i=this._events[t],n=this._events.all;return i&&u(i,e),n&&u(n,arguments),this},stopListening:function(t,e,n){var s=this._listeningTo;if(!s)return this;var r=!e&&!n;n||"object"!=typeof e||(n=this),t&&((s={})[t._listenId]=t);for(var a in s)t=s[a],t.off(e,n,this),(r||i.isEmpty(t._events))&&delete this._listeningTo[a];return this}},h=/\s+/,c=function(t,e,i,n){if(!i)return!0;if("object"==typeof i){for(var s in i)t[e].apply(t,[s,i[s]].concat(n));return!1}if(h.test(i)){for(var r=i.split(h),a=0,o=r.length;a<o;a++)t[e].apply(t,[r[a]].concat(n));return!1}return!0},u=function(t,e){var i,n=-1,s=t.length,r=e[0],a=e[1],o=e[2];switch(e.length){case 0:for(;++n<s;)(i=t[n]).callback.call(i.ctx);return;case 1:for(;++n<s;)(i=t[n]).callback.call(i.ctx,r);return;case 2:for(;++n<s;)(i=t[n]).callback.call(i.ctx,r,a);return;case 3:for(;++n<s;)(i=t[n]).callback.call(i.ctx,r,a,o);return;default:for(;++n<s;)(i=t[n]).callback.apply(i.ctx,e);return}},l={listenTo:"on",listenToOnce:"once"};i.each(l,function(t,e){o[e]=function(e,n,s){var r=this._listeningTo||(this._listeningTo={}),a=e._listenId||(e._listenId=i.uniqueId("l"));return r[a]=e,s||"object"!=typeof n||(s=this),e[t](n,s,this),this}}),o.bind=o.on,o.unbind=o.off,i.extend(e,o);var d=e.Model=function(t,e){var n=t||{};e||(e={}),this.cid=i.uniqueId("c"),this.attributes={},e.collection&&(this.collection=e.collection),e.parse&&(n=this.parse(n,e)||{}),n=i.defaults({},n,i.result(this,"defaults")),this.set(n,e),this.changed={},this.initialize.apply(this,arguments)};i.extend(d.prototype,o,{changed:null,validationError:null,idAttribute:"id",initialize:function(){},toJSON:function(t){return i.clone(this.attributes)},sync:function(){return e.sync.apply(this,arguments)},get:function(t){return this.attributes[t]},escape:function(t){return i.escape(this.get(t))},has:function(t){return null!=this.get(t)},set:function(t,e,n){var s,r,a,o,h,c,u,l;if(null==t)return this;if("object"==typeof t?(r=t,n=e):(r={})[t]=e,n||(n={}),!this._validate(r,n))return!1;a=n.unset,h=n.silent,o=[],c=this._changing,this._changing=!0,c||(this._previousAttributes=i.clone(this.attributes),this.changed={}),l=this.attributes,u=this._previousAttributes,this.idAttribute in r&&(this.id=r[this.idAttribute]);for(s in r)e=r[s],i.isEqual(l[s],e)||o.push(s),i.isEqual(u[s],e)?delete this.changed[s]:this.changed[s]=e,a?delete l[s]:l[s]=e;if(!h){o.length&&(this._pending=n);for(var d=0,f=o.length;d<f;d++)this.trigger("change:"+o[d],this,l[o[d]],n)}if(c)return this;if(!h)for(;this._pending;)n=this._pending,this._pending=!1,this.trigger("change",this,n);return this._pending=!1,this._changing=!1,this},unset:function(t,e){return this.set(t,void 0,i.extend({},e,{unset:!0}))},clear:function(t){var e={};for(var n in this.attributes)e[n]=void 0;return this.set(e,i.extend({},t,{unset:!0}))},hasChanged:function(t){return null==t?!i.isEmpty(this.changed):i.has(this.changed,t)},changedAttributes:function(t){if(!t)return!!this.hasChanged()&&i.clone(this.changed);var e,n=!1,s=this._changing?this._previousAttributes:this.attributes;for(var r in t)i.isEqual(s[r],e=t[r])||((n||(n={}))[r]=e);return n},previous:function(t){return null!=t&&this._previousAttributes?this._previousAttributes[t]:null},previousAttributes:function(){return i.clone(this._previousAttributes)},fetch:function(t){t=t?i.clone(t):{},void 0===t.parse&&(t.parse=!0);var e=this,n=t.success;return t.success=function(i){return!!e.set(e.parse(i,t),t)&&(n&&n(e,i,t),void e.trigger("sync",e,i,t))},U(this,t),this.sync("read",this,t)},save:function(t,e,n){var s,r,a,o=this.attributes;if(null==t||"object"==typeof t?(s=t,n=e):(s={})[t]=e,n=i.extend({validate:!0},n),s&&!n.wait){if(!this.set(s,n))return!1}else if(!this._validate(s,n))return!1;s&&n.wait&&(this.attributes=i.extend({},o,s)),void 0===n.parse&&(n.parse=!0);var h=this,c=n.success;return n.success=function(t){h.attributes=o;var e=h.parse(t,n);return n.wait&&(e=i.extend(s||{},e)),!(i.isObject(e)&&!h.set(e,n))&&(c&&c(h,t,n),void h.trigger("sync",h,t,n))},U(this,n),r=this.isNew()?"create":n.patch?"patch":"update","patch"===r&&(n.attrs=s),a=this.sync(r,this,n),s&&n.wait&&(this.attributes=o),a},destroy:function(t){t=t?i.clone(t):{};var e=this,n=t.success,s=function(){e.trigger("destroy",e,e.collection,t)};if(t.success=function(i){(t.wait||e.isNew())&&s(),n&&n(e,i,t),e.isNew()||e.trigger("sync",e,i,t)},this.isNew())return t.success(),!1;U(this,t);var r=this.sync("delete",this,t);return t.wait||s(),r},url:function(){var t=i.result(this,"urlRoot")||i.result(this.collection,"url")||j();return this.isNew()?t:t.replace(/([^\/])$/,"$1/")+encodeURIComponent(this.id)},parse:function(t,e){return t},clone:function(){return new this.constructor(this.attributes)},isNew:function(){return!this.has(this.idAttribute)},isValid:function(t){return this._validate({},i.extend(t||{},{validate:!0}))},_validate:function(t,e){if(!e.validate||!this.validate)return!0;t=i.extend({},this.attributes,t);var n=this.validationError=this.validate(t,e)||null;return!n||(this.trigger("invalid",this,n,i.extend(e,{validationError:n})),!1)}});var f=["keys","values","pairs","invert","pick","omit"];i.each(f,function(t){d.prototype[t]=function(){var e=a.call(arguments);return e.unshift(this.attributes),i[t].apply(i,e)}});var p=e.Collection=function(t,e){e||(e={}),e.model&&(this.model=e.model),void 0!==e.comparator&&(this.comparator=e.comparator),this._reset(),this.initialize.apply(this,arguments),t&&this.reset(t,i.extend({silent:!0},e))},g={add:!0,remove:!0,merge:!0},v={add:!0,remove:!1};i.extend(p.prototype,o,{model:d,initialize:function(){},toJSON:function(t){return this.map(function(e){return e.toJSON(t)})},sync:function(){return e.sync.apply(this,arguments)},add:function(t,e){return this.set(t,i.extend({merge:!1},e,v))},remove:function(t,e){var n=!i.isArray(t);t=n?[t]:i.clone(t),e||(e={});var s,r,a,o;for(s=0,r=t.length;s<r;s++)o=t[s]=this.get(t[s]),o&&(delete this._byId[o.id],delete this._byId[o.cid],a=this.indexOf(o),this.models.splice(a,1),this.length--,e.silent||(e.index=a,o.trigger("remove",o,this,e)),this._removeReference(o,e));return n?t[0]:t},set:function(t,e){e=i.defaults({},e,g),e.parse&&(t=this.parse(t,e));var n=!i.isArray(t);t=n?t?[t]:[]:i.clone(t);var s,r,a,o,h,c,u,l=e.at,f=this.model,p=this.comparator&&null==l&&e.sort!==!1,v=i.isString(this.comparator)?this.comparator:null,m=[],y=[],_={},b=e.add,w=e.merge,x=e.remove,E=!(p||!b||!x)&&[];for(s=0,r=t.length;s<r;s++){if(h=t[s]||{},a=h instanceof d?o=h:h[f.prototype.idAttribute||"id"],c=this.get(a))x&&(_[c.cid]=!0),w&&(h=h===o?o.attributes:h,e.parse&&(h=c.parse(h,e)),c.set(h,e),p&&!u&&c.hasChanged(v)&&(u=!0)),t[s]=c;else if(b){if(o=t[s]=this._prepareModel(h,e),!o)continue;m.push(o),this._addReference(o,e)}o=c||o,!E||!o.isNew()&&_[o.id]||E.push(o),_[o.id]=!0}if(x){for(s=0,r=this.length;s<r;++s)_[(o=this.models[s]).cid]||y.push(o);y.length&&this.remove(y,e)}if(m.length||E&&E.length)if(p&&(u=!0),this.length+=m.length,null!=l)for(s=0,r=m.length;s<r;s++)this.models.splice(l+s,0,m[s]);else{E&&(this.models.length=0);var k=E||m;for(s=0,r=k.length;s<r;s++)this.models.push(k[s])}if(u&&this.sort({silent:!0}),!e.silent){for(s=0,r=m.length;s<r;s++)(o=m[s]).trigger("add",o,this,e);(u||E&&E.length)&&this.trigger("sort",this,e)}return n?t[0]:t},reset:function(t,e){e||(e={});for(var n=0,s=this.models.length;n<s;n++)this._removeReference(this.models[n],e);return e.previousModels=this.models,this._reset(),t=this.add(t,i.extend({silent:!0},e)),e.silent||this.trigger("reset",this,e),t},push:function(t,e){return this.add(t,i.extend({at:this.length},e))},pop:function(t){var e=this.at(this.length-1);return this.remove(e,t),e},unshift:function(t,e){return this.add(t,i.extend({at:0},e))},shift:function(t){var e=this.at(0);return this.remove(e,t),e},slice:function(){return a.apply(this.models,arguments)},get:function(t){if(null!=t)return this._byId[t]||this._byId[t.id]||this._byId[t.cid]},at:function(t){return this.models[t]},where:function(t,e){return i.isEmpty(t)?e?void 0:[]:this[e?"find":"filter"](function(e){for(var i in t)if(t[i]!==e.get(i))return!1;return!0})},findWhere:function(t){return this.where(t,!0)},sort:function(t){if(!this.comparator)throw new Error("Cannot sort a set without a comparator");return t||(t={}),i.isString(this.comparator)||1===this.comparator.length?this.models=this.sortBy(this.comparator,this):this.models.sort(i.bind(this.comparator,this)),t.silent||this.trigger("sort",this,t),this},pluck:function(t){return i.invoke(this.models,"get",t)},fetch:function(t){t=t?i.clone(t):{},void 0===t.parse&&(t.parse=!0);var e=t.success,n=this;return t.success=function(i){var s=t.reset?"reset":"set";n[s](i,t),e&&e(n,i,t),n.trigger("sync",n,i,t)},U(this,t),this.sync("read",this,t)},create:function(t,e){if(e=e?i.clone(e):{},!(t=this._prepareModel(t,e)))return!1;e.wait||this.add(t,e);var n=this,s=e.success;return e.success=function(t,i){e.wait&&n.add(t,e),s&&s(t,i,e)},t.save(null,e),t},parse:function(t,e){return t},clone:function(){return new this.constructor(this.models)},_reset:function(){this.length=0,this.models=[],this._byId={}},_prepareModel:function(t,e){if(t instanceof d)return t;e=e?i.clone(e):{},e.collection=this;var n=new this.model(t,e);return n.validationError?(this.trigger("invalid",this,n.validationError,e),!1):n},_addReference:function(t,e){this._byId[t.cid]=t,null!=t.id&&(this._byId[t.id]=t),t.collection||(t.collection=this),t.on("all",this._onModelEvent,this)},_removeReference:function(t,e){this===t.collection&&delete t.collection,t.off("all",this._onModelEvent,this)},_onModelEvent:function(t,e,i,n){("add"!==t&&"remove"!==t||i===this)&&("destroy"===t&&this.remove(e,n),e&&t==="change:"+e.idAttribute&&(delete this._byId[e.previous(e.idAttribute)],null!=e.id&&(this._byId[e.id]=e)),this.trigger.apply(this,arguments))}});var m=["forEach","each","map","collect","reduce","foldl","inject","reduceRight","foldr","find","detect","filter","select","reject","every","all","some","any","include","contains","invoke","max","min","toArray","size","first","head","take","initial","rest","tail","drop","last","without","difference","indexOf","shuffle","lastIndexOf","isEmpty","chain","sample"];i.each(m,function(t){p.prototype[t]=function(){var e=a.call(arguments);return e.unshift(this.models),i[t].apply(i,e)}});var y=["groupBy","countBy","sortBy","indexBy"];i.each(y,function(t){p.prototype[t]=function(e,n){var s=i.isFunction(e)?e:function(t){return t.get(e)};return i[t](this.models,s,n)}});var _=e.View=function(t){this.cid=i.uniqueId("view"),t||(t={}),i.extend(this,i.pick(t,w)),this._ensureElement(),this.initialize.apply(this,arguments),this.delegateEvents()},b=/^(\S+)\s*(.*)$/,w=["model","collection","el","id","attributes","className","tagName","events"];i.extend(_.prototype,o,{tagName:"div",$:function(t){return this.$el.find(t)},initialize:function(){},render:function(){return this},remove:function(){return this.$el.remove(),this.stopListening(),this},setElement:function(t,i){return this.$el&&this.undelegateEvents(),this.$el=t instanceof e.$?t:e.$(t),this.el=this.$el[0],i!==!1&&this.delegateEvents(),this},delegateEvents:function(t){if(!t&&!(t=i.result(this,"events")))return this;this.undelegateEvents();for(var e in t){var n=t[e];if(i.isFunction(n)||(n=this[t[e]]),n){var s=e.match(b),r=s[1],a=s[2];n=i.bind(n,this),r+=".delegateEvents"+this.cid,""===a?this.$el.on(r,n):this.$el.on(r,a,n)}}return this},undelegateEvents:function(){return this.$el.off(".delegateEvents"+this.cid),this},_ensureElement:function(){if(this.el)this.setElement(i.result(this,"el"),!1);else{var t=i.extend({},i.result(this,"attributes"));this.id&&(t.id=i.result(this,"id")),this.className&&(t["class"]=i.result(this,"className"));var n=e.$("<"+i.result(this,"tagName")+">").attr(t);this.setElement(n,!1)}}}),e.sync=function(t,n,s){var r=E[t];i.defaults(s||(s={}),{emulateHTTP:e.emulateHTTP,emulateJSON:e.emulateJSON});var a={type:r,dataType:"json"};if(s.url||(a.url=i.result(n,"url")||j()),null!=s.data||!n||"create"!==t&&"update"!==t&&"patch"!==t||(a.contentType="application/json",a.data=JSON.stringify(s.attrs||n.toJSON(s))),s.emulateJSON&&(a.contentType="application/x-www-form-urlencoded",a.data=a.data?{model:a.data}:{}),s.emulateHTTP&&("PUT"===r||"DELETE"===r||"PATCH"===r)){a.type="POST",s.emulateJSON&&(a.data._method=r);var o=s.beforeSend;s.beforeSend=function(t){if(t.setRequestHeader("X-HTTP-Method-Override",r),o)return o.apply(this,arguments)}}"GET"===a.type||s.emulateJSON||(a.processData=!1),"PATCH"===a.type&&x&&(a.xhr=function(){return new ActiveXObject("Microsoft.XMLHTTP")});var h=s.xhr=e.ajax(i.extend(a,s));return n.trigger("request",n,h,s),h};var x=!("undefined"==typeof window||!window.ActiveXObject||window.XMLHttpRequest&&(new XMLHttpRequest).dispatchEvent),E={create:"POST",update:"PUT",patch:"PATCH","delete":"DELETE",read:"GET"};e.ajax=function(){return e.$.ajax.apply(e.$,arguments)};var k=e.Router=function(t){t||(t={}),t.routes&&(this.routes=t.routes),this._bindRoutes(),this.initialize.apply(this,arguments)},T=/\((.*?)\)/g,$=/(\(\?)?:\w+/g,S=/\*\w+/g,H=/[\-{}\[\]+?.,\\\^$|#\s]/g;i.extend(k.prototype,o,{initialize:function(){},route:function(t,n,s){i.isRegExp(t)||(t=this._routeToRegExp(t)),i.isFunction(n)&&(s=n,n=""),s||(s=this[n]);var r=this;return e.history.route(t,function(i){var a=r._extractParameters(t,i);r.execute(s,a),r.trigger.apply(r,["route:"+n].concat(a)),r.trigger("route",n,a),e.history.trigger("route",r,n,a)}),this},execute:function(t,e){t&&t.apply(this,e)},navigate:function(t,i){return e.history.navigate(t,i),this},_bindRoutes:function(){if(this.routes){this.routes=i.result(this,"routes");for(var t,e=i.keys(this.routes);null!=(t=e.pop());)this.route(t,this.routes[t])}},_routeToRegExp:function(t){return t=t.replace(H,"\\$&").replace(T,"(?:$1)?").replace($,function(t,e){return e?t:"([^/?]+)"}).replace(S,"([^?]*?)"),new RegExp("^"+t+"(?:\\?([\\s\\S]*))?$")},_extractParameters:function(t,e){var n=t.exec(e).slice(1);return i.map(n,function(t,e){return e===n.length-1?t||null:t?decodeURIComponent(t):null})}});var A=e.History=function(){this.handlers=[],i.bindAll(this,"checkUrl"),"undefined"!=typeof window&&(this.location=window.location,this.history=window.history)},I=/^[#\/]|\s+$/g,N=/^\/+|\/+$/g,R=/msie [\w.]+/,O=/\/$/,P=/#.*$/;A.started=!1,i.extend(A.prototype,o,{interval:50,atRoot:function(){return this.location.pathname.replace(/[^\/]$/,"$&/")===this.root},getHash:function(t){var e=(t||this).location.href.match(/#(.*)$/);return e?e[1]:""},getFragment:function(t,e){if(null==t)if(this._hasPushState||!this._wantsHashChange||e){t=decodeURI(this.location.pathname+this.location.search);var i=this.root.replace(O,"");t.indexOf(i)||(t=t.slice(i.length))}else t=this.getHash();return t.replace(I,"")},start:function(t){if(A.started)throw new Error("Backbone.history has already been started");A.started=!0,this.options=i.extend({root:"/"},this.options,t),this.root=this.options.root,this._wantsHashChange=this.options.hashChange!==!1,this._wantsPushState=!!this.options.pushState,this._hasPushState=!!(this.options.pushState&&this.history&&this.history.pushState);var n=this.getFragment(),s=document.documentMode,r=R.exec(navigator.userAgent.toLowerCase())&&(!s||s<=7);if(this.root=("/"+this.root+"/").replace(N,"/"),r&&this._wantsHashChange){var a=e.$('<iframe src="javascript:0" tabindex="-1">');this.iframe=a.hide().appendTo("body")[0].contentWindow,this.navigate(n)}this._hasPushState?e.$(window).on("popstate",this.checkUrl):this._wantsHashChange&&"onhashchange"in window&&!r?e.$(window).on("hashchange",this.checkUrl):this._wantsHashChange&&(this._checkUrlInterval=setInterval(this.checkUrl,this.interval)),this.fragment=n;var o=this.location;if(this._wantsHashChange&&this._wantsPushState){if(!this._hasPushState&&!this.atRoot())return this.fragment=this.getFragment(null,!0),this.location.replace(this.root+"#"+this.fragment),!0;this._hasPushState&&this.atRoot()&&o.hash&&(this.fragment=this.getHash().replace(I,""),this.history.replaceState({},document.title,this.root+this.fragment))}if(!this.options.silent)return this.loadUrl()},stop:function(){e.$(window).off("popstate",this.checkUrl).off("hashchange",this.checkUrl),this._checkUrlInterval&&clearInterval(this._checkUrlInterval),A.started=!1},route:function(t,e){this.handlers.unshift({route:t,callback:e})},checkUrl:function(t){var e=this.getFragment();return e===this.fragment&&this.iframe&&(e=this.getFragment(this.getHash(this.iframe))),e!==this.fragment&&(this.iframe&&this.navigate(e),void this.loadUrl())},loadUrl:function(t){return t=this.fragment=this.getFragment(t),i.any(this.handlers,function(e){if(e.route.test(t))return e.callback(t),!0})},navigate:function(t,e){if(!A.started)return!1;e&&e!==!0||(e={trigger:!!e});var i=this.root+(t=this.getFragment(t||""));if(t=t.replace(P,""),this.fragment!==t){if(this.fragment=t,""===t&&"/"!==i&&(i=i.slice(0,-1)),this._hasPushState)this.history[e.replace?"replaceState":"pushState"]({},document.title,i);else{if(!this._wantsHashChange)return this.location.assign(i);this._updateHash(this.location,t,e.replace),this.iframe&&t!==this.getFragment(this.getHash(this.iframe))&&(e.replace||this.iframe.document.open().close(),this._updateHash(this.iframe.location,t,e.replace))}return e.trigger?this.loadUrl(t):void 0}},_updateHash:function(t,e,i){if(i){var n=t.href.replace(/(javascript:|#).*$/,"");t.replace(n+"#"+e)}else t.hash="#"+e}}),e.history=new A;var C=function(t,e){var n,s=this;n=t&&i.has(t,"constructor")?t.constructor:function(){return s.apply(this,arguments)},i.extend(n,s,e);var r=function(){this.constructor=n};return r.prototype=s.prototype,n.prototype=new r,t&&i.extend(n.prototype,t),n.__super__=s.prototype,n};d.extend=p.extend=k.extend=_.extend=A.extend=C;var j=function(){throw new Error('A "url" property or function must be specified')},U=function(t,e){var i=e.error;e.error=function(n){i&&i(t,n,e),t.trigger("error",t,n,e)}};return e}),Backbone.View=function(t){return t.extend({constructor:function(e){this.options=e||{},t.apply(this,arguments)}})}(Backbone.View);