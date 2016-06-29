/*globals svgEditor */
svgEditor.readLang({
	lang: "mk",
	dir : "ltr",
	common: {
		"ok": "Зачувува",
		"cancel": "Откажи",
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
		"palette_info": "Кликни за да внесете промени бојата, промена клик да се промени бојата удар",
		"zoom_level": "Промена зум ниво",
		"panel_drag": "Drag left/right to resize side panel"
	},
	properties: {
		"id": "Identify the element",
		"fill_color": "Измени пополнете боја",
		"stroke_color": "Промена боја на мозочен удар",
		"stroke_style": "Промена удар цртичка стил",
		"stroke_width": "Промена удар Ширина",
		"pos_x": "Change X coordinate",
		"pos_y": "Change Y coordinate",
		"linecap_butt": "Linecap: Butt",
		"linecap_round": "Linecap: Round",
		"linecap_square": "Linecap: Square",
		"linejoin_bevel": "Linejoin: Bevel",
		"linejoin_miter": "Linejoin: Miter",
		"linejoin_round": "Linejoin: Round",
		"angle": "Change ротација агол",
		"blur": "Change gaussian blur value",
		"opacity": "Промена избрани ставка непроѕирноста",
		"circle_cx": "Промена круг на cx координира",
		"circle_cy": "Промена круг&#39;s cy координираат",
		"circle_r": "Промена на круг со радиус",
		"ellipse_cx": "Промена елипса&#39;s cx координираат",
		"ellipse_cy": "Промена на елипса cy координира",
		"ellipse_rx": "Промена на елипса x радиус",
		"ellipse_ry": "Промена на елипса у радиус",
		"line_x1": "Промена линија почетна x координира",
		"line_x2": "Промена линија завршува x координира",
		"line_y1": "Промена линија координираат почетна y",
		"line_y2": "Промена линија завршува y координира",
		"rect_height": "Промена правоаголник височина",
		"rect_width": "Промена правоаголник Ширина",
		"corner_radius": "Промена правоаголник Corner Radius",
		"image_width": "Промена Ширина на сликата",
		"image_height": "Промена на слика височина",
		"image_url": "Промена URL",
		"node_x": "Change node's x coordinate",
		"node_y": "Change node's y coordinate",
		"seg_type": "Change Segment type",
		"straight_segments": "Straight",
		"curve_segments": "Curve",
		"text_contents": "Промена текст содржина",
		"font_family": "Смени фонт Фамилија",
		"font_size": "Изменифонт Големина",
		"bold": "Задебелен текст",
		"italic": "Italic текст"
	},
	tools: { 
		"main_menu": "Main Menu",
		"bkgnd_color_opac": "Смени позадина / непроѕирноста",
		"connector_no_arrow": "No arrow",
		"fitToContent": "Способен да Содржина",
		"fit_to_all": "Способен да сите содржина",
		"fit_to_canvas": "Побиране да платно",
		"fit_to_layer_content": "Способен да слој содржина",
		"fit_to_sel": "Способен да селекција",
		"align_relative_to": "Порамни во поглед на ...",
		"relativeTo": "во поглед на:",
		"page": "страница",
		"largest_object": "најголемиот објект",
		"selected_objects": "избран објекти",
		"smallest_object": "најмалата објект",
		"new_doc": "Нови слики",
		"open_doc": "Отвори слика",
		"export_img": "Export",
		"save_doc": "Зачувај слика",
		"import_doc": "Import Image",
		"align_to_page": "Align Element to Page",
		"align_bottom": "Align Bottom",
		"align_center": "Центрирано",
		"align_left": "Порамни лево Порамни",
		"align_middle": "Израмни Среден",
		"align_right": "Порамни десно",
		"align_top": "Израмни почетокот",
		"mode_select": "Изберете ја алатката",
		"mode_fhpath": "Алатка за молив",
		"mode_line": "Line Tool",
		"mode_connect": "Connect two objects",
		"mode_rect": "Rectangle Tool",
		"mode_square": "Square Tool",
		"mode_fhrect": "Правоаголник слободна рака",
		"mode_ellipse": "Елипса",
		"mode_circle": "Круг",
		"mode_fhellipse": "Free-Hand Елипса",
		"mode_path": "Path Tool",
		"mode_shapelib": "Shape library",
		"mode_text": "Алатка за текст",
		"mode_image": "Алатка за сликата",
		"mode_zoom": "Алатка за зумирање",
		"mode_eyedropper": "Eye Dropper Tool",
		"no_embed": "NOTE: This image cannot be embedded. It will depend on this path to be displayed",
		"undo": "Врати",
		"redo": "Повтори",
		"tool_source": "Уреди Извор",
		"wireframe_mode": "Wireframe Mode",
		"toggle_grid": "Show/Hide Grid",
		"clone": "Clone Element(s)",
		"del": "Delete Element(s)",
		"group_elements": "Група на елементи",
		"make_link": "Make (hyper)link",
		"set_link_url": "Set link URL (leave empty to remove)",
		"to_path": "Convert to Path",
		"reorient_path": "Reorient path",
		"ungroup": "Ungroup Елементи",
		"docprops": "Својства на документот",
		"imagelib": "Image Library",
		"move_bottom": "Move to bottom",
		"move_top": "Поместување на почетокот",
		"node_clone": "Clone Node",
		"node_delete": "Delete Node",
		"node_link": "Link Control Points",
		"add_subpath": "Add sub-path",
		"openclose_path": "Open/close sub-path",
		"source_save": "Зачувува",
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
		"del": "Избриши Слој",
		"move_down": "Премести слој долу",
		"new": "Нов слој",
		"rename": "Преименувај слој",
		"move_up": "Премести слој горе",
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
		"select_predefined": "Изберете предефинирани:",
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
