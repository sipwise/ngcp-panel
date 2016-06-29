// DO NOT EDIT THIS FILE!
// THIS FILE IS JUST A SAMPLE; TO APPLY, YOU MUST
//   CREATE A NEW FILE config.js AND ADD CONTENTS
//   SUCH AS SHOWN BELOW INTO THAT FILE.

/*globals svgEditor*/
/*
The config.js file is intended for the setting of configuration or
  preferences which must run early on; if this is not needed, it is
  recommended that you create an extension instead (for greater
  reusability and modularity).
*/

// CONFIG AND EXTENSION SETTING
/*
See defaultConfig and defaultExtensions in svg-editor.js for a list
  of possible configuration settings.

See svg-editor.js for documentation on using setConfig().
*/

// URL OVERRIDE CONFIG
svgEditor.setConfig({
	/**
	To override the ability for URLs to set URL-based SVG content,
	    uncomment the following:
	*/
	// preventURLContentLoading: true,
	/**
	To override the ability for URLs to set other configuration (including
	    extensions), uncomment the following:
	*/
	// preventAllURLConfig: true,
	/**
	To override the ability for URLs to set their own extensions,
	  uncomment the following (note that if setConfig() is used in
	  extension code, it will still be additive to extensions,
	  however):
	*/
	// lockExtensions: true,
});

svgEditor.setConfig({
	/*
	Provide default values here which differ from that of the editor but
		which the URL can override
	*/
}, {allowInitialUserOverride: true});

// EXTENSION CONFIG
svgEditor.setConfig({
	extensions: [
        'ext-server_opensave.js'
		// 'ext-overview_window.js', 'ext-markers.js', 'ext-connector.js', 'ext-eyedropper.js', 'ext-shapes.js', 'ext-imagelib.js', 'ext-grid.js', 'ext-polygon.js', 'ext-star.js', 'ext-panning.js', 'ext-storage.js'
	]
	// , noDefaultExtensions: false, // noDefaultExtensions can only be meaningfully used in config.js or in the URL
});

// OTHER CONFIG
svgEditor.setConfig({	
	// canvasName: 'default',
	// canvas_expansion: 3,
	// initFill: {
		// color: 'FF0000', // solid red
		// opacity: 1
	// },
	// initStroke: {
		// width: 5,
		// color: '000000', // solid black
		// opacity: 1
	// },
	// initOpacity: 1,
	// colorPickerCSS: null,
	// initTool: 'select',
	// wireframe: false,
	// showlayers: false,
	// no_save_warning: false,
	// PATH CONFIGURATION
	// imgPath: 'images/',
	// langPath: 'locale/',
	// extPath: 'extensions/',
	// jGraduatePath: 'jgraduate/images/',
	// DOCUMENT PROPERTIES
	// dimensions: [640, 480],
	// EDITOR OPTIONS
	// gridSnapping: false,
	// gridColor: '#000',
	baseUnit: 'mm',
	// snappingStep: 10,
	// showRulers: true,
	// EXTENSION-RELATED (GRID)
	// showGrid: false, // Set by ext-grid.js
	// EXTENSION-RELATED (STORAGE)
	// noStorageOnLoad: false, // Some interaction with ext-storage.js; prevent even the loading of previously saved local storage
	// forceStorage: false, // Some interaction with ext-storage.js; strongly discouraged from modification as it bypasses user privacy by preventing them from choosing whether to keep local storage or not
	// emptyStorageOnDecline: true, // Used by ext-storage.js; empty any prior storage if the user declines to store
});

// PREF CHANGES
/**
setConfig() can also be used to set preferences in addition to
  configuration (see defaultPrefs in svg-editor.js for a list of
  possible settings), but at least if you are using ext-storage.js
  to store preferences, it will probably be better to let your
  users control these.
As with configuration, one may use allowInitialUserOverride, but
  in the case of preferences, any previously stored preferences
  will also thereby be enabled to override this setting (and at a
  higher priority than any URL preference setting overrides).
  Failing to use allowInitialUserOverride will ensure preferences
  are hard-coded here regardless of URL or prior user storage setting.
*/
svgEditor.setConfig(
	{
		// lang: '', // Set dynamically within locale.js if not previously set
		// iconsize: '', // Will default to 's' if the window height is smaller than the minimum height and 'm' otherwise
		/**
		* When showing the preferences dialog, svg-editor.js currently relies
		* on curPrefs instead of $.pref, so allowing an override for bkgd_color
		* means that this value won't have priority over block auto-detection as
		* far as determining which color shows initially in the preferences
		* dialog (though it can be changed and saved).
		*/
		// bkgd_color: '#FFF',
		// bkgd_url: '',
		img_save: 'embed',
		// Only shows in UI as far as alert notices
		// save_notice_done: false,
		// export_notice_done: false
	}
);
svgEditor.setConfig(
	{
		// Indicate pref settings here if you wish to allow user storage or URL settings
		//   to be able to override your default preferences (unless other config options
		//   have already explicitly prevented one or the other)
	},
	{allowInitialUserOverride: true}
);
