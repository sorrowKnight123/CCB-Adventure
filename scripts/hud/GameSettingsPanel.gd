extends Control

signal closed

@onready var total_slider: HSlider = $Center/Panel/Margin/VBox/TotalSlider
@onready var total_value: Label = $Center/Panel/Margin/VBox/TotalRow/Value
@onready var music_slider: HSlider = $Center/Panel/Margin/VBox/MusicSlider
@onready var music_value: Label = $Center/Panel/Margin/VBox/MusicRow/Value
@onready var sfx_slider: HSlider = $Center/Panel/Margin/VBox/SfxSlider
@onready var sfx_value: Label = $Center/Panel/Margin/VBox/SfxRow/Value


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	total_slider.value = AudioManager.get_total_volume()
	music_slider.value = AudioManager.get_music_volume()
	sfx_slider.value = AudioManager.get_sfx_volume()
	_update_value_label(total_value, total_slider.value)
	_update_value_label(music_value, music_slider.value)
	_update_value_label(sfx_value, sfx_slider.value)
	total_slider.value_changed.connect(_on_total_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	$Center/Panel/Margin/VBox/BackButton.pressed.connect(_on_back_pressed)


func _on_total_volume_changed(value: float) -> void:
	_update_value_label(total_value, value)
	AudioManager.set_total_volume(value)


func _on_music_volume_changed(value: float) -> void:
	_update_value_label(music_value, value)
	AudioManager.set_music_volume(value)


func _on_sfx_volume_changed(value: float) -> void:
	_update_value_label(sfx_value, value)
	AudioManager.set_sfx_volume(value)


func _update_value_label(label: Label, value: float) -> void:
	label.text = "%d" % int(round(value))


func _on_back_pressed() -> void:
	closed.emit()
