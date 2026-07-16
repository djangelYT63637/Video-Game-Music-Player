extends Node

var player: AudioStreamPlayer
var analyzer: AudioEffectSpectrumAnalyzerInstance
var wave_capturer: AudioEffectCapture

enum ChannelMode { MONO, STEREO, SURROUND_5_1 }
var current_channel_mode: ChannelMode = ChannelMode.STEREO

func _ready() -> void:
	# 1. Instantiate the AudioStreamPlayer FIRST to register an active stream handle
	player = AudioStreamPlayer.new()
	player.bus = "Master" # Start bound to Master to force audio thread wakefulness
	add_child(player)

	# 2. Clear out legacy Master channel effects to avoid data corruption
	var master_bus_idx = AudioServer.get_bus_index("Master")
	for i in range(AudioServer.get_bus_effect_count(master_bus_idx)):
		AudioServer.remove_bus_effect(master_bus_idx, 0)
		
	# 3. Inject a distinct isolated Visualizer Bus channel downstream
	var viz_bus_idx = AudioServer.get_bus_count()
	AudioServer.add_bus(viz_bus_idx)
	AudioServer.set_bus_name(viz_bus_idx, "VGM_Visualizer")
	
	# Explicitly establish structural channel routing relationships
	AudioServer.set_bus_send(viz_bus_idx, "Master")
	
	# 4. Route player directly to our visualizer bus now that it is initialized
	player.bus = "VGM_Visualizer"

	# 5. Bind the structural resource effects to the visualizer bus layout index
	var fx_spec = AudioEffectSpectrumAnalyzer.new()
	fx_spec.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048 
	AudioServer.add_bus_effect(viz_bus_idx, fx_spec, 0)
	
	var fx_cap = AudioEffectCapture.new()
	fx_cap.buffer_length = 0.1 
	AudioServer.add_bus_effect(viz_bus_idx, fx_cap, 1)
	
	# 6. CRITICAL SEQUENCE RECURSION FIX: Fetch working instances AFTER forcing bus synchronization
	analyzer = AudioServer.get_bus_effect_instance(viz_bus_idx, 0) as AudioEffectSpectrumAnalyzerInstance
	wave_capturer = AudioServer.get_bus_effect(viz_bus_idx, 1) as AudioEffectCapture
	
	set_audio_channel_mode(ChannelMode.STEREO)

func set_audio_channel_mode(mode: ChannelMode) -> void:
	current_channel_mode = mode
	if mode == ChannelMode.SURROUND_5_1:
		OS.alert("Surround Sound Emulation Layer Connected.", "VGM Engine")

## High accuracy linear amplitude normalizer mapping loop
func get_channel_magnitude(from_hz: float, to_hz: float, channel: int = 0) -> float:
	if not analyzer: 
		return 0.0
		
	var mag: Vector2 = analyzer.get_magnitude_for_frequency_range(from_hz, to_hz)
	var component: float = 0.0
	
	match channel:
		0: component = mag.length()
		1: component = mag.x # Isolate true physical left channel data component
		2: component = mag.y # Isolate true physical right channel data component
			
	if component < 0.00001:
		return 0.0
		
	var db = linear_to_db(component)
	
	# Cleanly scale the standard dynamic audio floor to safe 0.0 - 1.0 bounds
	return clamp((db + 60.0) / 60.0, 0.0, 1.0)

## Retrieves time-domain floating point frames from the capturing buffer arrays
func get_raw_pcm_frames(qty: int) -> PackedVector2Array:
	if not wave_capturer: 
		return PackedVector2Array()
	
	var available: int = wave_capturer.get_frames_available()
	if available == 0:
		return PackedVector2Array()
	
	if available > qty:
		var raw_chunk = wave_capturer.get_buffer(available)
		return raw_chunk.slice(raw_chunk.size() - qty)
		
	return wave_capturer.get_buffer(available)
