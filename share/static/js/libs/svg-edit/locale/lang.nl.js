/*globals svgEditor */
svgEditor.readLang({
	lang: "nl",
	dir : "ltr",
	common: {
		"ok": "Ok",
		"cancel": "Annuleren",
		"key_backspace": "backspace", 
		"key_del": "delete", 
		"key_down": "omlaag", 
		"key_up": "omhoog", 
		"more_opts": "More Options",
		"url": "URL",
		"width": "Width",
		"height": "Height"
	},
	misc: {
		"powered_by": "Mogelijk gemaakt door"
	}, 
	ui: {
		"toggle_stroke_tools": "Toon/verberg meer lijn gereedschap",
		"palette_info": "Klik om de vul kleur te veranderen, shift-klik om de lijn kleur te veranderen",
		"zoom_level": "In-/uitzoomen",
		"panel_drag": "Drag left/right to resize side panel"
	},
	properties: {
		"id": "Identificeer het element",
		"fill_color": "Verander vul kleur",
		"stroke_color": "Verander lijn kleur",
		"stroke_style": "Verander lijn stijl",
		"stroke_width": "Verander lijn breedte",
		"pos_x": "Verander X coordinaat",
		"pos_y": "Verander Y coordinaat",
		"linecap_butt": "Lijneinde: Geen",
		"linecap_round": "Lijneinde: Rond",
		"linecap_square": "Lijneinde: Vierkant",
		"linejoin_bevel": "Lijnverbinding: Afgestompt",
		"linejoin_miter": "Lijnverbinding: Hoek",
		"linejoin_round": "Lijnverbinding: Rond",
		"angle": "Draai",
		"blur": "Verander Gaussische vervaging waarde",
		"opacity": "Verander opaciteit geselecteerde item",
		"circle_cx": "Verander het X coordinaat van het cirkel middelpunt",
		"circle_cy": "Verander het Y coordinaat van het cirkel middelpunt",
		"circle_r": "Verander de cirkel radius",
		"ellipse_cx": "Verander het X coordinaat van het ellips middelpunt",
		"ellipse_cy": "Verander het Y coordinaat van het ellips middelpunt",
		"ellipse_rx": "Verander ellips X radius",
		"ellipse_ry": "Verander ellips Y radius",
		"line_x1": "Verander start X coordinaat van de lijn",
		"line_x2": "Verander eind X coordinaat van de lijn",
		"line_y1": "Verander start Y coordinaat van de lijn",
		"line_y2": "Verander eind Y coordinaat van de lijn",
		"rect_height": "Verander hoogte rechthoek",
		"rect_width": "Verander breedte rechthoek",
		"corner_radius": "Verander hoekradius rechthoek",
		"image_width": "Verander breedte afbeelding",
		"image_height": "Verander hoogte afbeelding",
		"image_url": "Verander URL",
		"node_x": "Verander X coordinaat knooppunt",
		"node_y": "Verander Y coordinaat knooppunt",
		"seg_type": "Verander segment type",
		"straight_segments": "Recht",
		"curve_segments": "Gebogen",
		"text_contents": "Wijzig tekst",
		"font_family": "Verander lettertype",
		"font_size": "Verander lettertype grootte",
		"bold": "Vet",
		"italic": "Cursief"
	},
	tools: { 
		"main_menu": "Hoofdmenu",
		"bkgnd_color_opac": "Verander achtergrond kleur/doorzichtigheid",
		"connector_no_arrow": "Geen pijl",
		"fitToContent": "Pas om inhoud",
		"fit_to_all": "Pas om alle inhoud",
		"fit_to_canvas": "Pas om canvas",
		"fit_to_layer_content": "Pas om laag inhoud",
		"fit_to_sel": "Pas om selectie",
		"align_relative_to": "Uitlijnen relatief ten opzichte van ...",
		"relativeTo": "Relatief ten opzichte van:",
		"Pagina": "Pagina",
		"largest_object": "Grootste object",
		"selected_objects": "Geselecteerde objecten",
		"smallest_object": "Kleinste object",
		"new_doc": "Nieuwe afbeelding",
		"open_doc": "Open afbeelding",
		"export_img": "Export",
		"save_doc": "Afbeelding opslaan",
		"import_doc": "Importeer SVG",
		"align_to_page": "Lijn element uit relatief ten opzichte van de pagina",
		"align_bottom": "Onder uitlijnen",
		"align_center": "Centreren",
		"align_left": "Links uitlijnen",
		"align_middle": "Midden uitlijnen",
		"align_right": "Rechts uitlijnen",
		"align_top": "Boven uitlijnen",
		"mode_select": "Selecteer",
		"mode_fhpath": "Potlood",
		"mode_line": "Lijn",
		"mode_connect": "Verbind twee objecten",
		"mode_rect": "Rectangle Tool",
		"mode_square": "Square Tool",
		"mode_fhrect": "Vrije stijl rechthoek",
		"mode_ellipse": "Ellips",
		"mode_circle": "Cirkel",
		"mode_fhellipse": "Vrije stijl ellips",
		"mode_path": "Pad",
		"mode_shapelib": "Shape library",
		"mode_text": "Tekst",
		"mode_image": "Afbeelding",
		"mode_zoom": "Zoom",
		"mode_eyedropper": "Kleuren kopieer gereedschap",
		"no_embed": "Let op: Dit plaatje kan niet worden geintegreerd (embeded). Het hangt af van dit pad om te worden afgebeeld.",
		"undo": "Ongedaan maken",
		"redo": "Opnieuw doen",
		"tool_source": "Bewerk bron",
		"wireframe_mode": "Draadmodel",
		"toggle_grid": "Show/Hide Grid",
		"clone": "Clone Element(s)",
		"del": "Delete Element(s)",
		"group_elements": "Groepeer elementen",
		"make_link": "Make (hyper)link",
		"set_link_url": "Set link URL (leave empty to remove)",
		"to_path": "Zet om naar pad",
		"reorient_path": "Herorienteer pad",
		"ungroup": "Groepering opheffen",
		"docprops": "Documenteigenschappen",
		"imagelib": "Image Library",
		"move_bottom": "Naar achtergrond",
		"move_top": "Naar voorgrond",
		"node_clone": "Kloon knooppunt",
		"node_delete": "Delete knooppunt",
		"node_link": "Koppel controle punten",
		"add_subpath": "Subpad toevoegen",
		"openclose_path": "Open/sluit subpad",
		"source_save": "Veranderingen toepassen",
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
		"layer":"Laag",
		"layers": "Layers",
		"del": "Delete laag",
		"move_down": "Beweeg laag omlaag",
		"new": "Nieuwe laag",
		"rename": "Hernoem laag",
		"move_up": "Beweeg laag omhoog",
		"dupe": "Duplicate Layer",
		"merge_down": "Merge Down",
		"merge_all": "Merge All",
		"move_elems_to": "Verplaats elementen naar:",
		"move_selected": "Verplaats geselecteerde elementen naar andere laag"
	},
	config: {
		"image_props": "Afbeeldingeigenschappen",
		"doc_title": "Titel",
		"doc_dims": "Canvas afmetingen",
		"included_images": "Ingesloten afbeeldingen",
		"image_opt_embed": "Toevoegen data (lokale bestanden)",
		"image_opt_ref": "Gebruik bestand referentie",
		"editor_prefs": "Editor eigenschappen",
		"icon_size": "Icoon grootte",
		"language": "Taal",
		"background": "Editor achtergrond",
		"editor_img_url": "Image URL",
		"editor_bg_note": "Let op: De achtergrond wordt niet opgeslagen met de afbeelding.",
		"icon_large": "Groot",
		"icon_medium": "Gemiddeld",
		"icon_small": "Klein",
		"icon_xlarge": "Extra groot",
		"select_predefined": "Kies voorgedefinieerd:",
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
		"invalidAttrValGiven":"Verkeerde waarde gegeven",
		"noContentToFitTo":"Geen inhoud om omheen te passen",
		"dupeLayerName":"Er is al een laag met die naam!",
		"enterUniqueLayerName":"Geef een unieke laag naam",
		"enterNewLayerName":"Geef een nieuwe laag naam",
		"layerHasThatName":"Laag heeft al die naam",
		"QmoveElemsToLayer":"Verplaats geselecteerde elementen naar laag '%s'?",
		"QwantToClear":"Wil je de afbeelding leeg maken?\nDit zal ook de ongedaan maak geschiedenis wissen!",
		"QwantToOpen":"Do you want to open a new file?\nThis will also erase your undo history!",
		"QerrorsRevertToSource":"Er waren analyse fouten in je SVG bron.\nTeruggaan naar de originele SVG bron?",
		"QignoreSourceChanges":"Veranderingen in de SVG bron negeren?",
		"featNotSupported":"Functie wordt niet ondersteund",
		"enterNewImgURL":"Geef de nieuwe afbeelding URL",
		"defsFailOnSave": "Let op: Vanwege een fout in je browser, kan dit plaatje verkeerd verschijnen (missende hoeken en/of elementen). Het zal goed verschijnen zodra het plaatje echt wordt opgeslagen.",
		"loadingImage":"Laden van het plaatje, even geduld aub...",
		"saveFromBrowser": "Kies \"Save As...\" in je browser om dit plaatje op te slaan als een %s bestand.",
		"noteTheseIssues": "Let op de volgende problemen: ",
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