extends Node

const VAULT_DIR = "user://vgm_vault/"
const PLAYLISTS_DIR = "user://vgm_playlists/"
const MANIFEST_FILE = "user://vgm_master_manifest.json"
const CONFIG_FILE = "user://vgm_hardware_config.json"

var master_library: Dictionary = {}  
var custom_playlists: Dictionary = {} 

func _ready() -> void:
	for dir in [VAULT_DIR, PLAYLISTS_DIR]:
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_absolute(dir)
	_load_master_records()

func import_track_to_vault(source_path: String) -> String:
	var ext = source_path.get_extension().to_lower()
	if not ext in ["mp3", "wav", "ogg"]: return ""
	
	var track_id = "trk_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)
	var target_path = VAULT_DIR + track_id + "." + ext
	
	var source = FileAccess.open(source_path, FileAccess.READ)
	if not source: return ""
	var buffer = source.get_buffer(source.get_length())
	
	var target = FileAccess.open(target_path, FileAccess.WRITE)
	if not target: return ""
	target.store_buffer(buffer)
	
	master_library[track_id] = {
		"title": source_path.get_file().get_basename().to_upper(),
		"ext": ext,
		"skipped": false # Persistent default skip flag
	}
	_save_master_records()
	return track_id

func toggle_track_skip_status(track_id: String) -> bool:
	if master_library.has(track_id):
		master_library[track_id]["skipped"] = not master_library[track_id].get("skipped", false)
		_save_master_records()
		return master_library[track_id]["skipped"]
	return false

func create_playlist(name: String) -> void:
	var clean_name = name.strip_edges().to_upper()
	if clean_name != "" and not custom_playlists.has(clean_name):
		custom_playlists[clean_name] = []
		save_playlist_to_disk(clean_name)

func add_track_to_playlist(playlist_name: String, track_id: String) -> void:
	if custom_playlists.has(playlist_name) and not track_id in custom_playlists[playlist_name]:
		custom_playlists[playlist_name].append(track_id)
		save_playlist_to_disk(playlist_name)

func remove_track_from_playlist(playlist_name: String, track_id: String) -> void:
	if custom_playlists.has(playlist_name):
		custom_playlists[playlist_name].erase(track_id)
		save_playlist_to_disk(playlist_name)

func get_track_stream(track_id: String) -> AudioStream:
	if not master_library.has(track_id): return null
	var track = master_library[track_id]
	var path = VAULT_DIR + track_id + "." + track["ext"]
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file: return null
	var bytes = file.get_buffer(file.get_length())
	
	match track["ext"]:
		"mp3":
			var stream = AudioStreamMP3.new()
			stream.data = bytes
			return stream
		"wav":
			var stream = AudioStreamWAV.new()
			stream.data = bytes
			return stream
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
	return null

func save_playlist_to_disk(playlist_name: String) -> void:
	var path = PLAYLISTS_DIR + playlist_name.validate_filename() + ".plt"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_var(custom_playlists[playlist_name])

func save_hardware_settings(settings: Dictionary) -> void:
	var file = FileAccess.open(CONFIG_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))

func load_hardware_settings() -> Dictionary:
	if FileAccess.file_exists(CONFIG_FILE):
		var file = FileAccess.open(CONFIG_FILE, FileAccess.READ)
		var json = JSON.parse_string(file.get_as_text())
		if json is Dictionary:
			return json
	return {}

func _save_master_records() -> void:
	var file = FileAccess.open(MANIFEST_FILE, FileAccess.WRITE)
	if file:
		var data = {"library": master_library}
		file.store_string(JSON.stringify(data))

func _load_master_records() -> void:
	if FileAccess.file_exists(MANIFEST_FILE):
		var file = FileAccess.open(MANIFEST_FILE, FileAccess.READ)
		var json = JSON.parse_string(file.get_as_text())
		if json and json.has("library"):
			master_library = json["library"]
			
	var dir = DirAccess.open(PLAYLISTS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".plt"):
				var plist_file = FileAccess.open(PLAYLISTS_DIR + file_name, FileAccess.READ)
				if plist_file:
					var p_name = file_name.get_basename().to_upper()
					custom_playlists[p_name] = plist_file.get_var()
			file_name = dir.get_next()
		dir.list_dir_end()
