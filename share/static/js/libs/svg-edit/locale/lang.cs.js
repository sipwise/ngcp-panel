/*globals svgEditor */
svgEditor.readLang({
	lang: "cs",
	dir : "ltr",
	common: {
		"ok": "Uložit",
		"cancel": "Storno",
		"key_backspace": "backspace", 
		"key_del": "delete", 
		"key_down": "šipka dolů", 
		"key_up": "šipka nahoru", 
		"more_opts": "More Options",
		"url": "URL",
		"width": "Width",
		"height": "Height"
	},
	misc: {
		"powered_by": "Běží na"
	}, 
	ui: {
		"toggle_stroke_tools": "Zobrazit/schovat více možností",
		"palette_info": "Kliknutím změníte barvu výplně, kliknutím současně s klávesou shift změníte barvu čáry",
		"zoom_level": "Změna přiblížení",
		"panel_drag": "Drag left/right to resize side panel"
	},
	properties: {
		"id": "Změnit ID elementu",
		"fill_color": "Změnit barvu výplně",
		"stroke_color": "Změnit barvu čáry",
		"stroke_style": "Změnit styl čáry",
		"stroke_width": "Změnit šířku čáry",
		"pos_x": "Změnit souřadnici X",
		"pos_y": "Změnit souřadnici Y",
		"linecap_butt": "Konec úsečky: přesný",
		"linecap_round": "Konec úsečky: zaoblený",
		"linecap_square": "Konec úsečky: s čtvercovým přesahem",
		"linejoin_bevel": "Styl napojení úseček: zkosené",
		"linejoin_miter": "Styl napojení úseček: ostré",
		"linejoin_round": "Styl napojení úseček: oblé",
		"angle": "Změnit úhel natočení",
		"blur": "Změnit rozostření",
		"opacity": "Změnit průhlednost objektů",
		"circle_cx": "Změnit souřadnici X středu kružnice",
		"circle_cy": "Změnit souřadnici Y středu kružnice",
		"circle_r": "Změnit poloměr kružnice",
		"ellipse_cx": "Změnit souřadnici X středu elipsy",
		"ellipse_cy": "Změnit souřadnici Y středu elipsy",
		"ellipse_rx": "Změnit poloměr X elipsy",
		"ellipse_ry": "Změnit poloměr Y elipsy",
		"line_x1": "Změnit počáteční souřadnici X úsečky",
		"line_x2": "Změnit koncovou souřadnici X úsečky",
		"line_y1": "Změnit počáteční souřadnici Y úsečky",
		"line_y2": "Změnit koncovou souřadnici X úsečky",
		"rect_height": "Změnit výšku obdélníku",
		"rect_width": "Změnit šířku obdélníku",
		"corner_radius": "Změnit zaoblení obdélníku",
		"image_width": "Změnit šířku dokumentu",
		"image_height": "Změnit výšku dokumentu",
		"image_url": "Změnit adresu URL",
		"node_x": "Změnit souřadnici X uzlu",
		"node_y": "Změnit souřadnici Y uzlu",
		"seg_type": "Změnit typ segmentu",
		"straight_segments": "úsečka",
		"curve_segments": "křivka",
		"text_contents": "Změnit text",
		"font_family": "Změnit font",
		"font_size": "Změnit velikost písma",
		"bold": "Tučně",
		"italic": "Kurzíva"
	},
	tools: { 
		"main_menu": "Hlavní menu",
		"bkgnd_color_opac": "Změnit barvu a průhlednost pozadí",
		"connector_no_arrow": "Bez šipky",
		"fitToContent": "přizpůsobit obsahu",
		"fit_to_all": "Přizpůsobit veškerému obsahu",
		"fit_to_canvas": "Přizpůsobit stránce",
		"fit_to_layer_content": "Přizpůsobit obsahu vrstvy",
		"fit_to_sel": "Přizpůsobit výběru",
		"align_relative_to": "Zarovnat relativně",
		"relativeTo": "relatativně k:",
		"page": "stránce",
		"largest_object": "největšímu objektu",
		"selected_objects": "zvoleným objektům",
		"smallest_object": "nejmenšímu objektu",
		"new_doc": "Nový dokument",
		"open_doc": "Otevřít dokument",
		"export_img": "Export",
		"save_doc": "Uložit dokument",
		"import_doc": "Importovat SVG",
		"align_to_page": "Zarovnat element na stránku",
		"align_bottom": "Zarovnat dolů",
		"align_center": "Zarovnat nastřed",
		"align_left": "Zarovnat doleva",
		"align_middle": "Zarovnat nastřed",
		"align_right": "Zarovnat doprava",
		"align_top": "Zarovnat nahoru",
		"mode_select": "Výběr a transformace objektů",
		"mode_fhpath": "Kresba od ruky",
		"mode_line": "Úsečka",
		"mode_connect": "Spojit dva objekty",
		"mode_rect": "Rectangle Tool",
		"mode_square": "Square Tool",
		"mode_fhrect": "Obdélník volnou rukou",
		"mode_ellipse": "Elipsa",
		"mode_circle": "Kružnice",
		"mode_fhellipse": "Elipsa volnou rukou",
		"mode_path": "Křivka",
		"mode_shapelib": "Shape library",
		"mode_text": "Text",
		"mode_image": "Obrázek",
		"mode_zoom": "Přiblížení",
		"mode_eyedropper": "Kapátko",
		"no_embed": "POZOR: Obrázek nelze uložit s dokumentem. Bude zobrazován z adresáře, kde se nyní nachází.",
		"undo": "Zpět",
		"redo": "Znovu",
		"tool_source": "Upravovat SVG kód",
		"wireframe_mode": "Zobrazit jen kostru",
		"toggle_grid": "Show/Hide Grid",
		"clone": "Clone Element(s)",
		"del": "Delete Element(s)",
		"group_elements": "Seskupit objekty",
		"make_link": "Make (hyper)link",
		"set_link_url": "Set link URL (leave empty to remove)",
		"to_path": "Objekt na křivku",
		"reorient_path": "Změna orientace křivky",
		"ungroup": "Zrušit seskupení",
		"docprops": "Vlastnosti dokumentu",
		"imagelib": "Image Library",
		"move_bottom": "Vrstvu úplně dospodu",
		"move_top": "Vrstvu úplně nahoru",
		"node_clone": "Vložit nový uzel",
		"node_delete": "Ostranit uzel",
		"node_link": "Provázat ovládací body uzlu",
		"add_subpath": "Přidat další součást křivky",
		"openclose_path": "Otevřít/zavřít součást křivky",
		"source_save": "Uložit",
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
		"layer":"Vrstva",
		"layers": "Layers",
		"del": "Odstranit vrstvu",
		"move_down": "Přesunout vrstvu níž",
		"new": "Přidat vrstvu",
		"rename": "Přejmenovat vrstvu",
		"move_up": "Přesunout vrstvu výš",
		"dupe": "Duplicate Layer",
		"merge_down": "Merge Down",
		"merge_all": "Merge All",
		"move_elems_to": "Přesunout objekty do:",
		"move_selected": "Přesunout objekty do jiné vrstvy"
	},
	config: {
		"image_props": "Vlastnosti dokumentu",
		"doc_title": "Název",
		"doc_dims": "Vlastní velikost",
		"included_images": "Vložené obrázky",
		"image_opt_embed": "Vkládat do dokumentu",
		"image_opt_ref": "Jen odkazem",
		"editor_prefs": "Nastavení editoru",
		"icon_size": "Velikost ikon",
		"language": "Jazyk",
		"background": "Obrázek v pozadí editoru",
		"editor_img_url": "Image URL",
		"editor_bg_note": "Pozor: obrázek v pozadí nebude uložen jako součást dokumentu.",
		"icon_large": "velké",
		"icon_medium": "střední",
		"icon_small": "malé",
		"icon_xlarge": "největší",
		"select_predefined": "vybrat předdefinovaný:",
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
		"invalidAttrValGiven":"Nevhodná hodnota",
		"noContentToFitTo":"Vyberte oblast pro přizpůsobení",
		"dupeLayerName":"Taková vrstva už bohužel existuje",
		"enterUniqueLayerName":"Zadejte prosím jedinečné jméno pro vrstvu",
		"enterNewLayerName":"Zadejte prosím jméno pro novou vrstvu",
		"layerHasThatName":"Vrstva už se tak jmenuje",
		"QmoveElemsToLayer":"Opravdu chcete přesunout vybrané objekty do vrstvy '%s'?",
		"QwantToClear":"Opravdu chcete smazat současný dokument?\nHistorie změn bude také smazána.",
		"QwantToOpen":"Do you want to open a new file?\nThis will also erase your undo history!",
		"QerrorsRevertToSource":"Chyba v parsování zdrojového kódu SVG.\nChcete se vrátit k původnímu?",
		"QignoreSourceChanges":"Opravdu chcete stornovat změny provedené v SVG kódu?",
		"featNotSupported":"Tato vlastnost ještě není k dispozici",
		"enterNewImgURL":"Vložte adresu URL, na které se nachází vkládaný obrázek",
		"defsFailOnSave": "POZOR: Kvůli nedokonalosti Vašeho prohlížeče se mohou některé části dokumentu špatně vykreslovat (mohou chybět barevné přechody nebo některé objekty). Po uložení dokumentu by se ale vše mělo zobrazovat správně.",
		"loadingImage":"Nahrávám obrázek ...",
		"saveFromBrowser": "Použijte nabídku \"Uložit stránku jako ...\" ve Vašem prohlížeči pro uložení dokumentu do souboru %s.",
		"noteTheseIssues": "Mohou se vyskytnout následující problémy: ",
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
