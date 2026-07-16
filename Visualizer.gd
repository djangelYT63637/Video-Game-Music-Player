extends Control

@export_enum("wave", "freq") var visualizer_mode: String = "freq"
@export var accent_color: Color = Color("#5de0a3")

var spectrum: AudioEffectSpectrumAnalyzerInstance
const BANDS_COUNT = 40
const MAX_FREQUENCY = 12000.0

func _ready() -> void:
	# Fetch the master audio bus layout reference
	var bus_index = AudioServer.get_bus_index("Master")
	
	# Loop inside the active audio effects chain to dynamically isolate our target analyzer
	for i in range(AudioServer.get_bus_effect_count(bus_index)):
		if AudioServer.get_bus_effect(bus_index, i) is AudioEffectSpectrumAnalyzer:
			spectrum = AudioServer.get_bus_effect_instance(bus_index, i)
			break

func _process(_delta: float) -> void:
	# Enforce custom frame drawing calls iteratively 
	queue_redraw()

func _draw() -> void:
	if not spectrum: return
	
	match visualizer_mode:
		"freq":
			draw_spectrum_bars()
		"wave":
			draw_oscilloscope_wave()

func draw_spectrum_bars() -> void:
	var bar_width = size.x / BANDS_COUNT
	var previous_hz = 0.0
	
	for i in range(BANDS_COUNT):
		var next_hz = (i + 1) * MAX_FREQUENCY / BANDS_COUNT
		var magnitude: Vector2 = spectrum.get_magnitude_for_frequency_range(previous_hz, next_hz)
		
		# Normalize linear energy conversion from decibel metrics
		var energy = clamp((magnitude.length() + 60.0) / 60.0, 0.0, 1.0)
		var bar_height = energy * size.y
		
		var x_pos = i * bar_width
		var y_pos = size.y - bar_height
		
		# Render frequency bar column arrays safely 
		draw_rect(Rect2(x_pos, y_pos, bar_width - 2, bar_height), accent_color)
		previous_hz = next_hz

func draw_oscilloscope_wave() -> void:
	var line_points = PackedVector2Array()
	var horizontal_step = size.x / BANDS_COUNT
	
	for i in range(BANDS_COUNT):
		var target_hz = (i + 1) * 3500.0 / BANDS_COUNT
		var frequency_energy = spectrum.get_magnitude_for_frequency_range(target_hz - 50, target_hz).length()
		
		# Formulate an interpolation cycle framework mapping values into physical offsets
		var wave_y_displacement = (frequency_energy * (size.y / 2.0)) * sin(i * 0.4)
		var x = i * horizontal_step
		var y = (size.y / 2.0) + wave_y_displacement
		
		line_points.append(Vector2(x, y))
		
	if line_points.size() > 1:
		draw_polyline(line_points, accent_color, 2.5, true)
		
	# Draw background median structural horizontal reference vector 
	draw_line(Vector2(0, size.y / 2.0), Vector2(size.x, size.y / 2.0), Color(1, 1, 1, 0.06), 1.0)
