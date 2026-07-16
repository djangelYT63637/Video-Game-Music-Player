extends Control

# --- Active Deck Runtime State ---
var current_playlist_name: String = ""
var runtime_track_queue: Array = []
var active_queue_index: int = -1
var is_seeking: bool = false
var app_is_in_view: bool = true
var playback_saved_position: float = 0.0

# Visual / Playlist State Parameters
var viz_mode: String = "SPECTRUM"   
var channel_split: String = "STEREO_SPLIT" 
var shuffle_active: bool = false
var loop_track_active: bool = false
var loop_list_active: bool = false
var playlist_sort_mode: String = "MANUAL"

# Frame Interpolation Buffers
var spectrum_lerp_left: Array[float] = []
var spectrum_lerp_right: Array[float] = []
const TOTAL_MONITOR_BANDS = 32
const VISUAL_SMOOTHING_FACTOR = 0.18

# Styling Guides
const CHASSIS_COLOR = Color("#141416")
const BASE_PANEL_COLOR = Color("#1e1e24")
const GLOW_BLUE = Color("#00bfff")
const GLOW_GREEN = Color("#32cd32")
const GLOW_AMBER = Color("#ff8c00")

# Node Anchors
var lbl_title: Label; var lbl_status: Label; var lbl_time: Label
var track_item_list: ItemList; var playlist_drawer_list: ItemList
var seek_bar: HSlider; var btn_play: Button; var visualizer_canvas: Control

# Option Element References
var opt_viz: OptionButton; var opt_split: OptionButton; var opt_sort: OptionButton
var c_shuf: CheckButton; var c_loop_t: CheckButton; var c_loop_l: CheckButton

# Overlay UI Drawers
var settings_overlay: PanelContainer
var txt_playlist_input: LineEdit

# FIXED: Global Native File Explorer System Node
var native_file_dialog: FileDialog

func _ready() -> void:
	spectrum_lerp_left.resize(TOTAL_MONITOR_BANDS)
	spectrum_lerp_right.resize(TOTAL_MONITOR_BANDS)
	spectrum_lerp_left.fill(0.0)
	spectrum_lerp_right.fill(0.0)
	
	_generate_hardware_deck_ui()
	_generate_modular_sub_drawers()
	_setup_native_file_explorer() # Initializes the true file system hook
	_apply_deserialized_settings()
	_refresh_playlist_drawer_view()
	
	VGMAudio.player.finished.connect(_on_playback_track_ended)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		app_is_in_view = false
		lbl_status.text = "STATUS: BACKGROUND ENERGY THROTTLE"
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		app_is_in_view = true
		lbl_status.text = "STATUS: INSTRUMENT PANEL RESTORED"

func _process(_delta: float) -> void:
	if VGMAudio.player.playing and not is_seeking:
		if VGMAudio.player.stream:
			seek_bar.max_value = VGMAudio.player.stream.get_length()
			seek_bar.value = VGMAudio.player.get_playback_position()
			_refresh_live_lcd_readouts()
	
	if visualizer_canvas and app_is_in_view:
		visualizer_canvas.queue_redraw()

# --- UI ARCHITECTURE BUILDER ENGINE ---

func _generate_hardware_deck_ui() -> void:
	anchor_right = 1.0; anchor_bottom = 1.0
	var bg = ColorRect.new(); bg.color = CHASSIS_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",12); margin.add_theme_constant_override("margin_top",12)
	margin.add_theme_constant_override("margin_right",12); margin.add_theme_constant_override("margin_bottom",12)
	add_child(margin)
	
	var main_layout = HBoxContainer.new(); main_layout.add_theme_constant_override("separation", 12)
	margin.add_child(main_layout)
	
	var center_chassis = PanelContainer.new(); center_chassis.size_flags_horizontal = SIZE_EXPAND_FILL; center_chassis.size_flags_stretch_ratio = 1.3
	_apply_box_style(center_chassis, BASE_PANEL_COLOR, 6, 2, Color("#2b2b35"))
	main_layout.add_child(center_chassis)
	
	var center_margin = MarginContainer.new()
	center_margin.add_theme_constant_override("margin_left",12); center_margin.add_theme_constant_override("margin_top",12)
	center_margin.add_theme_constant_override("margin_right",12); center_margin.add_theme_constant_override("margin_bottom",12)
	center_chassis.add_child(center_margin)
	
	var deck_vbox = VBoxContainer.new(); deck_vbox.add_theme_constant_override("separation", 10)
	center_margin.add_child(deck_vbox)
	
	var header = Label.new(); header.text = "VGM CORE DECK DEPLOYMENT RACK"; header.add_theme_font_size_override("font_size",11); header.add_theme_color_override("font_color", Color("#7f7f8f"))
	deck_vbox.add_child(header)
	
	var scr_blue = PanelContainer.new(); scr_blue.custom_minimum_size = Vector2(0, 48)
	_apply_box_style(scr_blue, Color("#020f1b"), 4, 2, GLOW_BLUE * 0.3); deck_vbox.add_child(scr_blue)
	var blue_m = MarginContainer.new(); blue_m.add_theme_constant_override("margin_left",10); blue_m.add_theme_constant_override("margin_right",10); scr_blue.add_child(blue_m)
	lbl_title = Label.new(); lbl_title.text = "DECK COLD // SYSTEM READY"; lbl_title.add_theme_color_override("font_color", GLOW_BLUE); lbl_title.add_theme_font_size_override("font_size", 14); lbl_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS; blue_m.add_child(lbl_title)
	
	var scr_green = PanelContainer.new(); scr_green.custom_minimum_size = Vector2(0, 40)
	_apply_box_style(scr_green, Color("#03140a"), 4, 2, GLOW_GREEN * 0.3); deck_vbox.add_child(scr_green)
	var green_m = MarginContainer.new(); green_m.add_theme_constant_override("margin_left",10); green_m.add_theme_constant_override("margin_right",10); scr_green.add_child(green_m)
	var green_hb = HBoxContainer.new(); green_m.add_child(green_hb)
	lbl_status = Label.new(); lbl_status.text = "STATUS: SYSTEM MONITORING TRUE"; lbl_status.size_flags_horizontal = SIZE_EXPAND_FILL; lbl_status.add_theme_color_override("font_color", GLOW_GREEN); lbl_status.add_theme_font_size_override("font_size", 12); green_hb.add_child(lbl_status)
	lbl_time = Label.new(); lbl_time.text = "00:00 [00:00]"; lbl_time.add_theme_color_override("font_color", GLOW_GREEN); lbl_time.add_theme_font_size_override("font_size", 12); green_hb.add_child(lbl_time)
	
	var scr_amber = PanelContainer.new(); scr_amber.size_flags_vertical = SIZE_EXPAND_FILL; scr_amber.custom_minimum_size = Vector2(0, 150)
	_apply_box_style(scr_amber, Color("#160a00"), 4, 2, GLOW_AMBER * 0.25); deck_vbox.add_child(scr_amber)
	visualizer_canvas = Control.new(); visualizer_canvas.size_flags_horizontal = SIZE_EXPAND_FILL; visualizer_canvas.size_flags_vertical = SIZE_EXPAND_FILL
	visualizer_canvas.draw.connect(_render_hardware_visualizer_pipeline); scr_amber.add_child(visualizer_canvas)
	
	seek_bar = HSlider.new(); seek_bar.step = 0.02; seek_bar.size_flags_horizontal = SIZE_EXPAND_FILL; deck_vbox.add_child(seek_bar)
	seek_bar.drag_started.connect(func(): is_seeking = true)
	seek_bar.drag_ended.connect(func(_changed): is_seeking = false; if VGMAudio.player.stream: VGMAudio.player.seek(seek_bar.value))
	
	var transport = HBoxContainer.new(); transport.add_theme_constant_override("separation", 6); deck_vbox.add_child(transport)
	var b_prev = Button.new(); b_prev.text = " ⏮ "; _style_retro_button(b_prev); transport.add_child(b_prev); b_prev.pressed.connect(_on_prev_clicked)
	btn_play = Button.new(); btn_play.text = " ▶ PLAY "; btn_play.custom_minimum_size = Vector2(85,0); _style_retro_button(btn_play, true); transport.add_child(btn_play); btn_play.pressed.connect(_on_play_toggle_clicked)
	var b_next = Button.new(); b_next.text = " ⏭ "; _style_retro_button(b_next); transport.add_child(b_next); b_next.pressed.connect(_on_next_clicked)
	var b_stop = Button.new(); b_stop.text = " ⏹ STOP "; _style_retro_button(b_stop); transport.add_child(b_stop); b_stop.pressed.connect(_on_stop_clicked)
	
	var spacer = Control.new(); spacer.size_flags_horizontal = SIZE_EXPAND_FILL; transport.add_child(spacer)
	var btn_settings = Button.new(); btn_settings.text = " 🛠 DECK CONFIG MATRIX "; _style_retro_button(btn_settings); transport.add_child(btn_settings)
	btn_settings.pressed.connect(func(): settings_overlay.visible = true)
	
	# Sidebar
	var sidebar_chassis = PanelContainer.new(); sidebar_chassis.size_flags_horizontal = SIZE_EXPAND_FILL; sidebar_chassis.size_flags_stretch_ratio = 0.75
	_apply_box_style(sidebar_chassis, BASE_PANEL_COLOR, 6, 2, Color("#2b2b35"))
	main_layout.add_child(sidebar_chassis)
	
	var side_margin = MarginContainer.new()
	side_margin.add_theme_constant_override("margin_left",10); side_margin.add_theme_constant_override("margin_top",10)
	side_margin.add_theme_constant_override("margin_right",10); side_margin.add_theme_constant_override("margin_bottom",10)
	sidebar_chassis.add_child(side_margin)
	
	var side_vbox = VBoxContainer.new(); side_vbox.add_theme_constant_override("separation", 8)
	side_margin.add_child(side_vbox)
	
	var lbl_p_title = Label.new(); lbl_p_title.text = "PLAYLIST INDEX CARTRIDGES"; lbl_p_title.add_theme_font_size_override("font_size",11); lbl_p_title.add_theme_color_override("font_color", Color("#7f7f8f"))
	side_vbox.add_child(lbl_p_title)
	
	playlist_drawer_list = ItemList.new(); playlist_drawer_list.custom_minimum_size = Vector2(0, 85)
	_apply_box_style(playlist_drawer_list, Color("#131317"), 2, 1, Color("#2c2c36"))
	playlist_drawer_list.item_activated.connect(_on_playlist_drawer_activated)
	side_vbox.add_child(playlist_drawer_list)
	
	var plist_input_hb = HBoxContainer.new(); side_vbox.add_child(plist_input_hb)
	txt_playlist_input = LineEdit.new(); txt_playlist_input.placeholder_text = "INITIALIZE RECORD ID..."; txt_playlist_input.size_flags_horizontal = SIZE_EXPAND_FILL; txt_playlist_input.add_theme_font_size_override("font_size",11)
	plist_input_hb.add_child(txt_playlist_input)
	var btn_add_plist = Button.new(); btn_add_plist.text = " [+] CREATE "; _style_retro_button(btn_add_plist, true); plist_input_hb.add_child(btn_add_plist)
	btn_add_plist.pressed.connect(_on_create_playlist_triggered)
	
	var lbl_t_title = Label.new(); lbl_t_title.text = "ACTIVE BUFFER MEMORY ARRAY QUEUE"; lbl_t_title.add_theme_font_size_override("font_size",11); lbl_t_title.add_theme_color_override("font_color", Color("#7f7f8f"))
	side_vbox.add_child(lbl_t_title)
	
	track_item_list = ItemList.new(); track_item_list.size_flags_vertical = SIZE_EXPAND_FILL
	_apply_box_style(track_item_list, Color("#131317"), 2, 1, Color("#2c2c36"))
	track_item_list.item_activated.connect(_on_track_queue_activated)
	side_vbox.add_child(track_item_list)
	
	var queue_utilities = HBoxContainer.new(); queue_utilities.add_theme_constant_override("separation", 4); side_vbox.add_child(queue_utilities)
	var btn_move_up = Button.new(); btn_move_up.text = "  🔼 UP  "; _style_retro_button(btn_move_up); queue_utilities.add_child(btn_move_up)
	btn_move_up.pressed.connect(func(): _execute_manual_queue_swap(-1))
	var btn_move_dn = Button.new(); btn_move_dn.text = "  🔽 DN  "; _style_retro_button(btn_move_dn); queue_utilities.add_child(btn_move_dn)
	btn_move_dn.pressed.connect(func(): _execute_manual_queue_swap(1))
	var btn_toggle_skip = Button.new(); btn_toggle_skip.text = " 🚫 TOGGLE SKIP "; _style_retro_button(btn_toggle_skip, true); queue_utilities.add_child(btn_toggle_skip)
	btn_toggle_skip.pressed.connect(_on_toggle_skip_clicked)
	
	var track_utilities_row = HBoxContainer.new(); track_utilities_row.add_theme_constant_override("separation", 5); side_vbox.add_child(track_utilities_row)
	
	# FIXED: Opens up standard native multiplatform file picker panel directly
	var btn_add_track = Button.new(); btn_add_track.text = " 📥 IMPORT FROM DEVICE STORAGE "; _style_retro_button(btn_add_track, true); btn_add_track.size_flags_horizontal = SIZE_EXPAND_FILL; track_utilities_row.add_child(btn_add_track)
	btn_add_track.pressed.connect(func(): if current_playlist_name != "": native_file_dialog.popup_centered_ratio(0.7) else: lbl_status.text = "STATUS: SELECT A CARTRIDGE PLAYLIST FIRST")
	
	var btn_skip_track = Button.new(); btn_skip_track.text = " ⏩ FORCE "; _style_retro_button(btn_skip_track); track_utilities_row.add_child(btn_skip_track)
	btn_skip_track.pressed.connect(_on_skip_selected_track_triggered)
	var btn_remove_track = Button.new(); btn_remove_track.text = " [❌] PURGE "; _style_retro_button(btn_remove_track); track_utilities_row.add_child(btn_remove_track)
	btn_remove_track.pressed.connect(_on_remove_selected_track_triggered)

func _generate_modular_sub_drawers() -> void:
	settings_overlay = PanelContainer.new(); settings_overlay.visible = false; settings_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim = StyleBoxFlat.new(); dim.bg_color = Color(0,0,0,0.85); settings_overlay.add_theme_stylebox_override("panel", dim); add_child(settings_overlay)
	
	var sm = MarginContainer.new(); sm.add_theme_constant_override("margin_left",60); sm.add_theme_constant_override("margin_top",60); sm.add_theme_constant_override("margin_right",60); sm.add_theme_constant_override("margin_bottom",60); settings_overlay.add_child(sm)
	var sc = PanelContainer.new(); _apply_box_style(sc, BASE_PANEL_COLOR, 6, 2, GLOW_GREEN); sm.add_child(sc)
	var si = MarginContainer.new(); si.add_theme_constant_override("margin_left",16); si.add_theme_constant_override("margin_top",16); si.add_theme_constant_override("margin_right",16); si.add_theme_constant_override("margin_bottom",16); sc.add_child(si)
	var sv = VBoxContainer.new(); sv.add_theme_constant_override("separation",12); si.add_child(sv)
	
	var st = Label.new(); st.text = "HARDWARE CONSOLE PREFERENCES LOGIC ENGINE"; st.add_theme_color_override("font_color", GLOW_GREEN); st.add_theme_font_size_override("font_size",14); sv.add_child(st)
	
	var hb_v1 = HBoxContainer.new(); sv.add_child(hb_v1)
	var l_v1 = Label.new(); l_v1.text = "INSTRUMENT VIEW RENDER METHOD: "; l_v1.size_flags_horizontal = SIZE_EXPAND_FILL; hb_v1.add_child(l_v1)
	opt_viz = OptionButton.new(); opt_viz.add_item("LOGARITHMIC FREQUENCY SPECTRUM (GRID METERS)"); opt_viz.add_item("REALTIME TIME-DOMAIN PCM OSCILLOSCOPE BEAM"); hb_v1.add_child(opt_viz)
	opt_viz.item_selected.connect(func(id): viz_mode = "SPECTRUM" if id == 0 else "OSCILLOSCOPE"; _serialize_current_hardware_settings())
	
	var hb_v2 = HBoxContainer.new(); sv.add_child(hb_v2)
	var l_v2 = Label.new(); l_v2.text = "VISUALIZER HARDWARE TRACK POSITION MAPPING: "; l_v2.size_flags_horizontal = SIZE_EXPAND_FILL; hb_v2.add_child(l_v2)
	opt_split = OptionButton.new(); opt_split.add_item("WHOLE COMBINED CHANNEL MIX"); opt_split.add_item("INTEGRATED STEREO SEPARATION ARRAY (L / R CHANNEL COMPONENT SPLIT)"); hb_v2.add_child(opt_split)
	opt_split.item_selected.connect(func(id): channel_split = "WHOLE" if id == 0 else "STEREO_SPLIT"; _serialize_current_hardware_settings())
	
	var hb_sort = HBoxContainer.new(); sv.add_child(hb_sort)
	var l_sort = Label.new(); l_sort.text = "PLAYLIST INDEX AUTOMATED SORT ORDER ENGINE: "; l_sort.size_flags_horizontal = SIZE_EXPAND_FILL; hb_sort.add_child(l_sort)
	opt_sort = OptionButton.new(); opt_sort.add_item("MANUAL CHRONOLOGICAL RE-ORDERING ARCHIVE"); opt_sort.add_item("AUTOMATED ALPHABETICAL / NUMERICAL PASS"); hb_sort.add_child(opt_sort)
	opt_sort.item_selected.connect(_on_sorting_preference_changed)
	
	var flow_ops = HFlowContainer.new(); flow_ops.add_theme_constant_override("h_separation",8); flow_ops.add_theme_constant_override("v_separation",8); sv.add_child(flow_ops)
	c_shuf = CheckButton.new(); c_shuf.text = "SHUFFLE ACTIVE RANDOMIZER"; flow_ops.add_child(c_shuf); c_shuf.toggled.connect(func(b): shuffle_active = b; _serialize_current_hardware_settings())
	c_loop_t = CheckButton.new(); c_loop_t.text = "LOOP RUNNING SINGLE TRACK RECORD"; flow_ops.add_child(c_loop_t); c_loop_t.toggled.connect(func(b): loop_track_active = b; _serialize_current_hardware_settings())
	c_loop_l = CheckButton.new(); c_loop_l.text = "LOOP CURRENT DRAWER PACK COMPLETELY"; flow_ops.add_child(c_loop_l); c_loop_l.toggled.connect(func(b): loop_list_active = b; _serialize_current_hardware_settings())
	
	var close_s = Button.new(); close_s.text = " 💾 WRITE CONFIG TO APPLICATION VAULT DISK "; _style_retro_button(close_s, true); sv.add_child(close_s)
	close_s.pressed.connect(func(): settings_overlay.visible = false)

# --- FIXED: SEAMLESS NATIVE INTERFACE FILE EXPLORER CONFIGURATION ---

func _setup_native_file_explorer() -> void:
	native_file_dialog = FileDialog.new()
	native_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	native_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	native_file_dialog.title = "SELECT CHIP TRACK AUDIO FILES FOR PLAYLIST INJECTION"
	
	# Explicitly define targets across common platforms
	native_file_dialog.add_filter("*.mp3", "MPEG Audio Layer III")
	native_file_dialog.add_filter("*.wav", "Waveform Audio Format")
	native_file_dialog.add_filter("*.ogg", "Ogg Vorbis Stream Audio")
	
	# Fall back to standard User documents/downloads shortcuts automatically
	native_file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	
	native_file_dialog.files_selected.connect(_on_native_files_compiled_for_injection)
	add_child(native_file_dialog)

func _on_native_files_compiled_for_injection(paths: PackedStringArray) -> void:
	if current_playlist_name == "": return
	
	var successfully_imported_count = 0
	for path in paths:
		var trk_id = VGMDatabase.import_track_to_vault(path)
		if trk_id != "":
			VGMDatabase.add_track_to_playlist(current_playlist_name, trk_id)
			successfully_imported_count += 1
			
	_load_playlist_into_active_queue(current_playlist_name, false)
	lbl_status.text = "STATUS: SUCCESSFUL INJECTION OF " + str(successfully_imported_count) + " TRACK CARTRIDGES"

# --- CONFIG MATRIX CONTROLLERS ---

func _serialize_current_hardware_settings() -> void:
	var settings = {
		"viz_mode": viz_mode,
		"channel_split": channel_split,
		"playlist_sort_mode": playlist_sort_mode,
		"shuffle_active": shuffle_active,
		"loop_track_active": loop_track_active,
		"loop_list_active": loop_list_active
	}
	VGMDatabase.save_hardware_settings(settings)

func _apply_deserialized_settings() -> void:
	var s = VGMDatabase.load_hardware_settings()
	if s.is_empty(): return
	viz_mode = s.get("viz_mode", "SPECTRUM")
	channel_split = s.get("channel_split", "STEREO_SPLIT")
	playlist_sort_mode = s.get("playlist_sort_mode", "MANUAL")
	shuffle_active = s.get("shuffle_active", false)
	loop_track_active = s.get("loop_track_active", false)
	loop_list_active = s.get("loop_list_active", false)
	
	opt_viz.select(0 if viz_mode == "SPECTRUM" else 1)
	opt_split.select(0 if channel_split == "WHOLE" else 1)
	opt_sort.select(0 if playlist_sort_mode == "MANUAL" else 1)
	c_shuf.button_pressed = shuffle_active
	c_loop_t.button_pressed = loop_track_active
	c_loop_l.button_pressed = loop_list_active

func _execute_manual_queue_swap(direction: int) -> void:
	if current_playlist_name == "" or playlist_sort_mode == "ALPHABETICAL": return
	var selected = track_item_list.get_selected_items()
	if selected.is_empty(): return
	var src_idx = selected[0]
	var dest_idx = src_idx + direction
	if dest_idx < 0 or dest_idx >= runtime_track_queue.size(): return
	
	var holding_id = runtime_track_queue[src_idx]
	runtime_track_queue[src_idx] = runtime_track_queue[dest_idx]
	runtime_track_queue[dest_idx] = holding_id
	
	if active_queue_index == src_idx: active_queue_index = dest_idx
	elif active_queue_index == dest_idx: active_queue_index = src_idx
	
	VGMDatabase.save_playlist_to_disk(current_playlist_name)
	_load_playlist_into_active_queue(current_playlist_name, false)
	track_item_list.select(dest_idx)

func _on_sorting_preference_changed(index: int) -> void:
	playlist_sort_mode = "MANUAL" if index == 0 else "ALPHABETICAL"
	_serialize_current_hardware_settings()
	if current_playlist_name != "":
		_load_playlist_into_active_queue(current_playlist_name, true)

func _on_toggle_skip_clicked() -> void:
	var selected = track_item_list.get_selected_items()
	if selected.is_empty(): return
	var trk_id = runtime_track_queue[selected[0]]
	VGMDatabase.toggle_track_skip_status(trk_id)
	_update_track_list_display_text()

# --- RUNTIME PLAYBACK SEQUENCES WITH AUTOMATED SKIP DETECTION ---

func _refresh_playlist_drawer_view() -> void:
	playlist_drawer_list.clear()
	for p_name in VGMDatabase.custom_playlists.keys():
		playlist_drawer_list.add_item(p_name)

func _load_playlist_into_active_queue(playlist_name: String, reset_playback: bool = true) -> void:
	current_playlist_name = playlist_name
	runtime_track_queue = VGMDatabase.custom_playlists[playlist_name]
	
	if playlist_sort_mode == "ALPHABETICAL":
		runtime_track_queue.sort_custom(func(a, b):
			var title_a = VGMDatabase.master_library.get(a, {}).get("title", "")
			var title_b = VGMDatabase.master_library.get(b, {}).get("title", "")
			return title_a < title_b
		)
	_update_track_list_display_text()
	lbl_title.text = "ACTIVE INTERFACE DRIVE: " + playlist_name
	if reset_playback: _on_stop_clicked()

func _update_track_list_display_text() -> void:
	track_item_list.clear()
	for i in range(runtime_track_queue.size()):
		var trk_id = runtime_track_queue[i]
		if VGMDatabase.master_library.has(trk_id):
			var item = VGMDatabase.master_library[trk_id]
			var display = "  " + item["title"]
			if item.get("skipped", false):
				display += " [SKIPPED]"
			track_item_list.add_item(display)
			if i == active_queue_index:
				track_item_list.set_item_custom_bg_color(i, Color(0, 0.4, 0.2, 0.4))

func _execute_track_loading_sequence(idx: int) -> void:
	if idx < 0 or idx >= runtime_track_queue.size(): return
	active_queue_index = idx
	var trk_id = runtime_track_queue[active_queue_index]
	
	var stream = VGMDatabase.get_track_stream(trk_id)
	if stream:
		VGMAudio.player.stream = stream
		_update_track_list_display_text()
		track_item_list.select(active_queue_index)
		lbl_title.text = "PLAYING TRK: " + VGMDatabase.master_library[trk_id]["title"]
		seek_bar.value = 0
		playback_saved_position = 0.0
		if btn_play.text.contains("PAUSE") or VGMAudio.player.playing:
			VGMAudio.player.play()
			lbl_status.text = "STATUS: OUTPUT CHANNELS BUSY"
		else:
			lbl_status.text = "STATUS: TRACK COLD ARMED"
		_refresh_live_lcd_readouts()

# --- AUTO-ADVANCEMENT TRAVERSAL WITH SKIP VALIDATION ---

func _on_next_clicked() -> void:
	if runtime_track_queue.is_empty(): return
	
	var all_skipped = true
	for t_id in runtime_track_queue:
		if not VGMDatabase.master_library.get(t_id, {}).get("skipped", false):
			all_skipped = false
			break
	if all_skipped:
		_on_stop_clicked()
		lbl_status.text = "STATUS: ALL TRACKS SKIPPED"
		return

	var next_idx = active_queue_index
	var checked_count = 0
	
	while checked_count <= runtime_track_queue.size():
		if shuffle_active:
			next_idx = randi() % runtime_track_queue.size()
		else:
			next_idx += 1
			if next_idx >= runtime_track_queue.size():
				if loop_list_active: next_idx = 0
				else: _on_stop_clicked(); return
				
		var potential_id = runtime_track_queue[next_idx]
		if not VGMDatabase.master_library.get(potential_id, {}).get("skipped", false):
			_execute_track_loading_sequence(next_idx)
			return
		checked_count += 1
	_on_stop_clicked()

func _on_prev_clicked() -> void:
	if runtime_track_queue.is_empty(): return
	var prev_idx = active_queue_index
	var checked_count = 0
	while checked_count <= runtime_track_queue.size():
		prev_idx -= 1
		if prev_idx < 0: prev_idx = runtime_track_queue.size() - 1
		var potential_id = runtime_track_queue[prev_idx]
		if not VGMDatabase.master_library.get(potential_id, {}).get("skipped", false):
			_execute_track_loading_sequence(prev_idx)
			return
		checked_count += 1

func _on_play_toggle_clicked() -> void:
	if VGMAudio.player.playing:
		playback_saved_position = VGMAudio.player.get_playback_position()
		VGMAudio.player.stop()
		btn_play.text = " ▶ PLAY "
		lbl_status.text = "STATUS: DECK SUSPEND PAUSE"
	else:
		if VGMAudio.player.stream:
			VGMAudio.player.play(playback_saved_position)
			btn_play.text = " ▮▮ PAUSE "
			lbl_status.text = "STATUS: RESUMING OUTPUT AUDIO"

func _on_stop_clicked() -> void:
	VGMAudio.player.stop(); VGMAudio.player.seek(0); seek_bar.value = 0
	playback_saved_position = 0.0
	btn_play.text = " ▶ PLAY "; lbl_status.text = "STATUS: DECK RESET COLD"

func _on_skip_selected_track_triggered() -> void:
	if track_item_list.get_selected_items().size() > 0:
		_execute_track_loading_sequence(track_item_list.get_selected_items()[0])
		VGMAudio.player.play()
		btn_play.text = " ▮▮ PAUSE "

func _on_remove_selected_track_triggered() -> void:
	if current_playlist_name == "": return
	var selected = track_item_list.get_selected_items()
	if selected.is_empty(): return
	var target_idx = selected[0]
	VGMDatabase.remove_track_from_playlist(current_playlist_name, runtime_track_queue[target_idx])
	if target_idx == active_queue_index: _on_stop_clicked()
	_load_playlist_into_active_queue(current_playlist_name, false)

func _on_playback_track_ended() -> void:
	if loop_track_active:
		VGMAudio.player.seek(0); VGMAudio.player.play()
	else: _on_next_clicked()

func _refresh_live_lcd_readouts() -> void:
	var cur = int(VGMAudio.player.get_playback_position())
	var tot = int(VGMAudio.player.stream.get_length()) if VGMAudio.player.stream else 0
	lbl_time.text = "%02d:%02d [%02d:%02d]" % [int(cur/60), cur%60, int(tot/60), tot%60]

func _on_create_playlist_triggered() -> void:
	var id_text = txt_playlist_input.text.strip_edges()
	if id_text != "":
		VGMDatabase.create_playlist(id_text)
		txt_playlist_input.clear()
		_refresh_playlist_drawer_view()

func _on_playlist_drawer_activated(index: int) -> void:
	_load_playlist_into_active_queue(VGMDatabase.custom_playlists.keys()[index], true)

func _on_track_queue_activated(index: int) -> void:
	_execute_track_loading_sequence(index)
	VGMAudio.player.play()
	btn_play.text = " ▮▮ PAUSE "

# --- 🎨 TRUE TIME-DOMAIN REAL-TIME PCM OSCILLOSCOPE DRAW PIPELINE ---

func _render_hardware_visualizer_pipeline() -> void:
	if not visualizer_canvas: return
	var canvas_size = visualizer_canvas.size
	
	if viz_mode == "SPECTRUM":
		var total_render_lanes = TOTAL_MONITOR_BANDS
		var bar_width = canvas_size.x / total_render_lanes
		var prev_hz = 20.0
		var ceiling_hz = 12000.0
		
		for i in range(total_render_lanes):
			var next_hz = prev_hz * pow(ceiling_hz / 20.0, 1.0 / total_render_lanes)
			var target_left_energy = 0.0
			var target_right_energy = 0.0
			
			if channel_split == "STEREO_SPLIT":
				target_left_energy = VGMAudio.get_channel_magnitude(prev_hz, next_hz, 1)
				target_right_energy = VGMAudio.get_channel_magnitude(prev_hz, next_hz, 2)
			else:
				var baseline = VGMAudio.get_channel_magnitude(prev_hz, next_hz, 0)
				target_left_energy = baseline
				target_right_energy = baseline
				
			spectrum_lerp_left[i] = lerp(spectrum_lerp_left[i], target_left_energy, VISUAL_SMOOTHING_FACTOR)
			spectrum_lerp_right[i] = lerp(spectrum_lerp_right[i], target_right_energy, VISUAL_SMOOTHING_FACTOR)
			
			var x_pos = i * bar_width
			var total_grid_blocks = int((canvas_size.y - 14) / 6)
			
			if channel_split == "STEREO_SPLIT":
				var splitting_line_y = canvas_size.y / 2.0
				var half_blocks = int(total_grid_blocks / 2)
				
				var active_l_blocks = int(spectrum_lerp_left[i] * half_blocks)
				for slot in range(active_l_blocks):
					var sy = splitting_line_y - (slot * 5) - 4
					var c = Color("#ff2222") if slot > int(half_blocks * 0.78) else GLOW_AMBER
					visualizer_canvas.draw_rect(Rect2(x_pos + 1.0, sy, bar_width - 2, 3.5), c)
					
				var active_r_blocks = int(spectrum_lerp_right[i] * half_blocks)
				for slot in range(active_r_blocks):
					var sy = splitting_line_y + (slot * 5) + 2
					var c = Color("#ff2222") if slot > int(half_blocks * 0.78) else GLOW_AMBER
					visualizer_canvas.draw_rect(Rect2(x_pos + 1.0, sy, bar_width - 2, 3.5), c)
			else:
				var active_blocks = int(spectrum_lerp_left[i] * total_grid_blocks)
				for slot in range(active_blocks):
					var sy = canvas_size.y - (slot * 6) - 6
					var c = Color("#ff2222") if slot > int(total_grid_blocks * 0.78) else GLOW_AMBER
					visualizer_canvas.draw_rect(Rect2(x_pos + 1.0, sy, bar_width - 2, 4), c)
			prev_hz = next_hz
			
		if channel_split == "STEREO_SPLIT":
			visualizer_canvas.draw_line(Vector2(0, canvas_size.y / 2.0), Vector2(canvas_size.x, canvas_size.y / 2.0), Color("#7f3d00", 0.4), 1.5)
			
	elif viz_mode == "OSCILLOSCOPE":
		var sampling_density = 160
		var pcm_data: PackedVector2Array = VGMAudio.get_raw_pcm_frames(sampling_density)
		
		if pcm_data.is_empty():
			var center_y = canvas_size.y / 2.0
			visualizer_canvas.draw_line(Vector2(0, center_y), Vector2(canvas_size.x, center_y), GLOW_AMBER * 0.4, 1.5)
			return
			
		var horizontal_step = canvas_size.x / float(pcm_data.size() - 1)
		
		if channel_split == "STEREO_SPLIT":
			var points_l = PackedVector2Array()
			var points_r = PackedVector2Array()
			var left_center_y = canvas_size.y * 0.25
			var right_center_y = canvas_size.y * 0.75
			var amplification = canvas_size.y * 0.22
			
			for i in range(pcm_data.size()):
				var frame = pcm_data[i]
				var x = i * horizontal_step
				points_l.append(Vector2(x, left_center_y + (frame.x * amplification)))
				points_r.append(Vector2(x, right_center_y + (frame.y * amplification)))
				
			visualizer_canvas.draw_polyline(points_l, GLOW_AMBER, 1.8, true)
			visualizer_canvas.draw_polyline(points_r, GLOW_AMBER * 0.75, 1.8, true)
		else:
			var points = PackedVector2Array()
			var center_y = canvas_size.y / 2.0
			var amplification = canvas_size.y * 0.45
			
			for i in range(pcm_data.size()):
				var frame = pcm_data[i]
				var mixed_sample = (frame.x + frame.y) / 2.0
				var x = i * horizontal_step
				points.append(Vector2(x, center_y + (mixed_sample * amplification)))
				
			visualizer_canvas.draw_polyline(points, GLOW_AMBER, 2.0, true)

func _apply_box_style(node: Control, bg: Color, rad: int, bw: int, border_color: Color = Color("#32323a")) -> void:
	var s = StyleBoxFlat.new(); s.bg_color = bg; s.set_corner_radius_all(rad); s.set_border_width_all(bw); s.border_color = border_color
	node.add_theme_stylebox_override("panel", s)

func _style_retro_button(b: Button, high: bool = false) -> void:
	var n = StyleBoxFlat.new(); n.bg_color = Color("#24242c") if not high else Color("#2a3545")
	n.set_border_width_all(1); n.border_color = Color("#3d3d4d") if not high else GLOW_BLUE
	n.set_corner_radius_all(3)
	var p = n.duplicate(); p.bg_color = Color("#111115")
	b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", p); b.add_theme_color_override("font_color", Color("#c4c4d4") if not high else GLOW_BLUE)
	b.add_theme_font_size_override("font_size", 11)
