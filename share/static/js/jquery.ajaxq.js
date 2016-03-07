;(function(root) {
  'use strict';

  var $ = root.jQuery || root.Zepto || root.$;

  if (typeof $ === 'undefined') throw 'jquery.ajaxq requires jQuery or jQuery-compatible library (e.g. Zepto.js)';

  /**
   * @type {Function}
   */
  var slice = Array.prototype.slice;

  /**
   * @type {Function}
   */
  var noop = function() {};

  /**
   * Copy of jQuery function
   * @type {Function}
   */
  var isNumeric = function(obj) {
    return !$.isArray( obj ) && (obj - parseFloat( obj ) + 1) >= 0;
  }

  /**
   * @type {Function}
   */
  var isObject = function(obj) {
    return "[object Object]" === Object.prototype.toString.call(obj);
  }


  var Request = (function (argument) {

    function Request(url, settings) {
      this._aborted   = false;
      this._jqXHR     = null;
      this._calls     = {};
      this._args      = [url, settings];
      this._deferred  = $.Deferred();

      this._deferred.pipe = this._deferred.then;

      this.readyState = 1;
    }

    var proto = Request.prototype;

    $.extend(proto, {

      // start jqXHR by calling $.ajax
      run: function() {
        var
          deferred = this._deferred,
          methodName, argsStack, i;

        if (this._jqXHR !== null) {
          return this._jqXHR;
        }
        // clreate new jqXHR object
        var
          url = this._args[0],
          settings = this._args[1];

        if (isObject(url)) {
          settings = url;
        } else {
          settings = $.extend(true, settings || {}, {
            url: url
          });
        }

        this._jqXHR = $.ajax.call($, settings);

        this._jqXHR.done(function() {
          deferred.resolve.apply(deferred, arguments);
        });

        this._jqXHR.fail(function() {
          deferred.reject.apply(deferred, arguments);
        });

        if (this._aborted) {
          this._jqXHR.abort(this.statusText);
        }

        // apply buffered calls
        for (methodName in this._calls) {
          argsStack = this._calls[methodName];
          for (var i in argsStack) {
            this._jqXHR[methodName].apply(this._jqXHR, argsStack[i]);
          }
        }

        return this._jqXHR;
      },

      // returns original jqXHR object if it exists
      // or writes to callected method to _calls and returns itself
      _call: function(methodName, args) {
        if (this._jqXHR !== null) {
          if (typeof this._jqXHR[methodName] === 'undefined') {
            return this._jqXHR;
          }
          return this._jqXHR[methodName].apply(this._jqXHR, args);
        }

        this._calls[methodName] = this._calls[methodName] || [];
        this._calls[methodName].push(args);

        return this;
      },

      // returns original jqXHR object if it exists
      // or writes to callected method to _calls and returns itself
      abort: function(statusText) {
        if (this._jqXHR !== null) {
          var
            self = this,
            _copyProperties = ['readyState', 'status', 'statusText'],
            _return = this._jqXHR.abort.apply(this._jqXHR, arguments) || this._jqXHR;

          if (_return) {
            $.each(_copyProperties, function(i, prop) {
              self[prop] = _return[prop];
            });
          }

          return _return;
        }

        this.statusText = statusText || 'abort';
        this.status     = 0;
        this.readyState = 0;
        this._aborted   = true;

        return this;
      },
      state: function() {
        if (this._jqXHR !== null) {
          return this._jqXHR.state.apply(this._jqXHR, arguments);
        }
        return 'pending';
      }
    });

    // each method returns self object
    var _chainMethods = ['setRequestHeader', 'overrideMimeType', 'statusCode',
      'done', 'fail', 'progress', 'complete', 'success', 'error', 'always' ];

    $.each(_chainMethods, function(i, methodName) {
      proto[methodName] = function() {
        return this._call(methodName, slice.call(arguments)) || this._jqXHR;
      }
    });

    var _nullMethods = ['getResponseHeader', 'getAllResponseHeaders'];

    $.each(_nullMethods, function(i, methodName) {
      proto[methodName] = function() {
        // apply original method if _jqXHR exists
        if (this._jqXHR !== null) {
          return this._jqXHR[methodName].apply(this, arguments);
        }

        // return null if origina method does not exists
        return null;
      };
    });

    var _promiseMethods = ['pipe', 'then', 'promise'];

    $.each(_promiseMethods, function(i, methodName) {
      proto[methodName] = function() {
        return this._deferred[methodName].apply(this._deferred, arguments);
      };
    });

    return Request;
  })()
  var Queue = (function() {

    var _params = {}, _queueCounter = 0;

    function _runNext(queue, request) {
      var
        removeIndex = _getStarted(queue).indexOf(request),
        nextRequest = _getPending(queue).shift();

      if (removeIndex !== -1) {
        _getStarted(queue).splice(removeIndex, 1);
      }

      if (typeof nextRequest !== 'undefined') {
        nextRequest
          .always($.proxy(_runNext, null, queue, nextRequest))
          .run();
      }
    }

    function _ajax(queue, request) {
      if (_getStarted(queue).length < _getBandwidth(queue)) {
        _getStarted(queue).push(request);
        request.always($.proxy(_runNext, null, queue, request));
        request.run();
      } else {
        _getPending(queue).push(request)
      }
    }

    function _getParams(queue) {
      return _params[queue.id] || (_params[queue.id] = {});
    }

    function _getParam(queue, name) {
      return _getParams(queue)[name];
    }

    function _getStarted(queue) {
      return _getParams(queue).started || (_getParams(queue).started = []);
    }

    function _getPending(queue) {
      return _getParams(queue).pending || (_getParams(queue).pending = []);
    }

    function _setBandwidth(queue, bandwidth) {
      if ((bandwidth = parseInt(bandwidth || 1, 10)) < 1) throw "Bandwidth can\'t be less then 1";
      _getParams(queue).bandwidth = bandwidth;
    }

    function _getBandwidth(queue, bandwidth) {
      return _getParams(queue).bandwidth;
    }

    function Queue(bandwidth) {
      if (typeof bandwidth !== 'undefined' && !isNumeric(bandwidth)) throw "number expected";
      this.id = ++_queueCounter;
      _setBandwidth(this, bandwidth);
    };

    $.extend(Queue.prototype, {
      ajax: function(url, settings) {
        var request = new Request(url, settings);
        _ajax(this, request);
        return request;
      },
      getJSON: function ( url, data, callback ) {
        return this.get( url, data, callback, "json" );
      },
      getBandwidth: function() {
        return _getBandwidth(this);
      }
    });

    $.each(['get', 'post'], function(i, method) {
      Queue.prototype[method] = function( url, data, callback, type ) {
        // shift arguments if data argument was omitted
        if ( $.isFunction( data ) ) {
          type = type || callback;
          callback = data;
          data = undefined;
        }

        return this.ajax({
          url: url,
          type: method,
          dataType: type,
          data: data,
          success: callback
        });
      }
    });

    return Queue;
  })();

  if (typeof $.ajaxq !== 'undefined') throw "Namespace $.ajaxq is Alread y busy.";

  var _queue = new Queue();

  $.ajaxq = function(url, settions) {
    return _queue.ajax.apply(_queue, arguments);
  };

  $.each(['get', 'post', 'getJSON'], function(i, methodName) {
    $.ajaxq[methodName] = function() {
      return _queue[methodName].apply(_queue, arguments);
    }
  });

  $.ajaxq.Queue = function(bandwidth) {
    return new Queue(bandwidth);
  };

  $.ajaxq.Request = function(url, settings) {
    return new Request(url, settings);
  }

})(this);
