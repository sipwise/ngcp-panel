/*globals svgEditor */
svgEditor.readLang({
	lang: "cy",
	dir : "ltr",
	common: {
		"ok": "Cadw",
		"cancel": "Canslo",
		"key_backspace": "backspace", 
		"key_del": "delete", 
		"key_down": "down", 
		"key_up": "up", 
		"more_opts": "More Options",
		"url": "URL",
		"width": "Width",
		"height": "Height"
	},
	misc: {
		"powered_by": "Powered by"
	}, 
	ui: {
		"toggle_stroke_tools": "Show/hide more stroke tools",
		"palette_info": "Cliciwch yma i lenwi newid lliw, sifft-cliciwch i newid lliw strôc",
		"zoom_level": "Newid lefel chwyddo",
		"panel_drag": "Drag left/right to resize side panel"
	},
	properties: {
		"id": "Identify the element",
		"fill_color": "Newid lliw llenwi",
		"stroke_color": "Newid lliw strôc",
		"stroke_style": "Newid arddull strôc diferyn",
		"stroke_width": "Lled strôc Newid",
		"pos_x": "Change X coordinate",
		"pos_y": "Change Y coordinate",
		"linecap_butt": "Linecap: Butt",
		"linecap_round": "Linecap: Round",
		"linecap_square": "Linecap: Square",
		"linejoin_bevel": "Linejoin: Bevel",
		"linejoin_miter": "Linejoin: Miter",
		"linejoin_round": "Linejoin: Round",
		"angle": "Ongl cylchdro Newid",
		"blur": "Change gaussian blur value",
		"opacity": "Newid dewis Didreiddiad eitem",
		"circle_cx": "CX Newid cylch yn cydlynu",
		"circle_cy": "Newid cylch&#39;s cy gydgysylltu",
		"circle_r": "Newid radiws cylch yn",
		"ellipse_cx": "Newid Ellipse yn CX gydgysylltu",
		"ellipse_cy": "Newid Ellipse yn cydlynu cy",
		"ellipse_rx": "Radiws Newid Ellipse&#39;s x",
		"ellipse_ry": "Radiws Newid Ellipse yn y",
		"line_x1": "Newid llinell yn cychwyn x gydgysylltu",
		"line_x2": "Newid llinell yn diweddu x gydgysylltu",
		"line_y1": "Newid llinell ar y cychwyn yn cydlynu",
		"line_y2": "Newid llinell yn dod i ben y gydgysylltu",
		"rect_height": "Uchder petryal Newid",
		"rect_width": "Lled petryal Newid",
		"corner_radius": "Newid Hirsgwâr Corner Radiws",
		"image_width": "Lled delwedd Newid",
		"image_height": "Uchder delwedd Newid",
		"image_url": "Newid URL",
		"node_x": "Change node's x coordinate",
		"node_y": "Change node's y coordinate",
		"seg_type": "Change Segment type",
		"straight_segments": "Straight",
		"curve_segments": "Curve",
		"text_contents": "Cynnwys testun Newid",
		"font_family": "Newid Font Teulu",
		"font_size": "Newid Maint Ffont",
		"bold": "Testun Bras",
		"italic": "Italig Testun"
	},
	tools: { 
		"main_menu": "Main Menu",
		"bkgnd_color_opac": "Newid lliw cefndir / Didreiddiad",
		"connector_no_arrow": "No arrow",
		"fitToContent": "Ffit i Cynnwys",
		"fit_to_all": "Yn addas i bawb content",
		"fit_to_canvas": "Ffit i ofyn",
		"fit_to_layer_content": "Ffit cynnwys haen i",
		"fit_to_sel": "Yn addas at ddewis",
		"align_relative_to": "Alinio perthynas i ...",
		"relativeTo": "cymharol i:",
		"page": "tudalen",
		"largest_object": "gwrthrych mwyaf",
		"selected_objects": "gwrthrychau etholedig",
		"smallest_object": "lleiaf gwrthrych",
		"new_doc": "Newydd Delwedd",
		"open_doc": "Delwedd Agored",
		"export_img": "Export",
		"save_doc": "Cadw Delwedd",
		"import_doc": "Import Image",
		"align_to_page": "Align Element to Page",
		"align_bottom": "Alinio Gwaelod",
		"align_center": "Alinio Center",
		"align_left": "Alinio Chwith",
		"align_middle": "Alinio Canol",
		"align_right": "Alinio Hawl",
		"align_top": "Alinio Top",
		"mode_select": "Dewiswch Offer",
		"mode_fhpath": "Teclyn pensil",
		"mode_line": "Llinell Offer",
		"mode_connect": "Connect two objects",
		"mode_rect": "Rectangle Tool",
		"mode_square": "Square Tool",
		"mode_fhrect": "Hand rhad ac am ddim Hirsgwâr",
		"mode_ellipse": "Ellipse",
		"mode_circle": "Cylch",
		"mode_fhellipse": "Rhad ac am ddim Hand Ellipse",
		"mode_path": "Offer poly",
		"mode_shapelib": "Shape library",
		"mode_text": "Testun Offer",
		"mode_image": "Offer Delwedd",
		"mode_zoom": "Offer Chwyddo",
		"mode_eyedropper": "Eye Dropper Tool",
		"no_embed": "NOTE: This image cannot be embedded. It will depend on this path to be displayed",
		"undo": "Dadwneud",
		"redo": "Ail-wneud",
		"tool_source": "Golygu Ffynhonnell",
		"wireframe_mode": "Wireframe Mode",
		"toggle_grid": "Show/Hide Grid",
		"clone": "Clone Element(s)",
		"del": "Delete Element(s)",
		"group_elements": "Elfennau Grŵp",
		"make_link": "Make (hyper)link",
		"set_link_url": "Set link URL (leave empty to remove)",
		"to_path": "Convert to Path",
		"reorient_path": "Reorient path",
		"ungroup": "Elfennau Ungroup",
		"docprops": "Document Eiddo",
		"imagelib": "Image Library",
		"move_bottom": "Symud i&#39;r Gwaelod",
		"move_top": "Symud i&#39;r Top",
		"node_clone": "Clone Node",
		"node_delete": "Delete Node",
		"node_link": "Link Control Points",
		"add_subpath": "Add sub-path",
		"openclose_path": "Open/close sub-path",
		"source_save": "Cadw",
		"cut": "Cut",
		"copy": "Copy",
		"paste": "Paste",
		"paste_in_place": "Paste in Place",
		"delete": "Delete",
		"group": "Group",
		"move_front": "Bring to Front",
		"move_up": "Bring Forward",
		"move_down": "Send Backward",
		"move_back": "Send to Back"
	},
	layers: {
		"layer":"Layer",
		"layers": "Layers",
		"del": "Dileu Haen",
		"move_down": "Symud Haen i Lawr",
		"new": "Haen Newydd",
		"rename": "Ail-enwi Haen",
		"move_up": "Symud Haen Up",
		"dupe": "Duplicate Layer",
		"merge_down": "Merge Down",
		"merge_all": "Merge All",
		"move_elems_to": "Move elements to:",
		"move_selected": "Move selected elements to a different layer"
	},
	config: {
		"image_props": "Image Properties",
		"doc_title": "Title",
		"doc_dims": "Canvas Dimensions",
		"included_images": "Included Images",
		"image_opt_embed": "Embed data (local files)",
		"image_opt_ref": "Use file reference",
		"editor_prefs": "Editor Preferences",
		"icon_size": "Icon size",
		"language": "Language",
		"background": "Editor Background",
		"editor_img_url": "Image URL",
		"editor_bg_note": "Note: Background will not be saved with image.",
		"icon_large": "Large",
		"icon_medium": "Medium",
		"icon_small": "Small",
		"icon_xlarge": "Extra Large",
		"select_predefined": "Rhagosodol Dewis:",
		"units_and_rulers": "Units & Rulers",
		"show_rulers": "Show rulers",
		"base_unit": "Base Unit:",
		"grid": "Grid",
		"snapping_onoff": "Snapping on/off",
		"snapping_stepsize": "Snapping Step-Size:",
		"grid_color": "Grid color"
	},
	shape_cats: {
		"basic": "Basic",
		"object": "Objects",
		"symbol": "Symbols",
		"arrow": "Arrows",
		"flowchart": "Flowchart",
		"animal": "Animals",
		"game": "Cards & Chess",
		"dialog_balloon": "Dialog balloons",
		"electronics": "Electronics",
		"math": "Mathematical",
		"music": "Music",
		"misc": "Miscellaneous",
		"raphael_1": "raphaeljs.com set 1",
		"raphael_2": "raphaeljs.com set 2"
	},
	imagelib: {
		"select_lib": "Select an image library",
		"show_list": "Show library list",
		"import_single": "Import single",
		"import_multi": "Import multiple",
		"open": "Open as new document"
	},
	notification: {
		"invalidAttrValGiven":"Invalid value given",
		"noContentToFitTo":"No content to fit to",
		"dupeLayerName":"There is already a layer named that!",
		"enterUniqueLayerName":"Please enter a unique layer name",
		"enterNewLayerName":"Please enter the new layer name",
		"layerHasThatName":"Layer already has that name",
		"QmoveElemsToLayer":"Move selected elements to layer '%s'?",
		"QwantToClear":"Do you want to clear the drawing?\nThis will also erase your undo history!",
		"QwantToOpen":"Do you want to open a new file?\nThis will also erase your undo history!",
		"QerrorsRevertToSource":"There were parsing errors in your SVG source.\nRevert back to original SVG source?",
		"QignoreSourceChanges":"Ignore changes made to SVG source?",
		"featNotSupported":"Feature not supported",
		"enterNewImgURL":"Enter the new image URL",
		"defsFailOnSave": "NOTE: Due to a bug in your browser, this image may appear wrong (missing gradients or elements). It will however appear correct once actually saved.",
		"loadingImage":"Loading image, please wait...",
		"saveFromBrowser": "Select \"Save As...\" in your browser to save this image as a %s file.",
		"noteTheseIssues": "Also note the following issues: ",
		"unsavedChanges": "There are unsaved changes.",
		"enterNewLinkURL": "Enter the new hyperlink URL",
		"errorLoadingSVG": "Error: Unable to load SVG data",
		"URLloadFail": "Unable to load from URL",
		"retrieving": "Retrieving \"%s\"..."
	},
	confirmSetStorage: {
		message: "By default and where supported, SVG-Edit can store your editor "+
		"preferences and SVG content locally on your machine so you do not "+
		"need to add these back each time you load SVG-Edit. If, for privacy "+
		"reasons, you do not wish to store this information on your machine, "+
		"you can change away from the default option below.",
		storagePrefsAndContent: "Store preferences and SVG content locally",
		storagePrefsOnly: "Only store preferences locally",
		storagePrefs: "Store preferences locally",
		storageNoPrefsOrContent: "Do not store my preferences or SVG content locally",
		storageNoPrefs: "Do not store my preferences locally",
		rememberLabel: "Remember this choice?",
		rememberTooltip: "If you choose to opt out of storage while remembering this choice, the URL will change so as to avoid asking again."
	}
});
