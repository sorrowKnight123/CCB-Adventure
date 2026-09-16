extends Node
## 全局音乐管理器：负责背景音乐、临时音乐覆盖、淡入淡出和播放位置恢复。

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "audio"
const DEFAULT_VOLUME := 60.0
const DEFAULT_SFX_EFFECTIVE_VOLUME := 20.0
const FADE_DURATION := 1.0
const BACKGROUND_STREAM: AudioStream = preload("res://audio/music/La_Cathédrale_engloutie_-_Claude_Debussy_-_performed_by_Ivan_Ilic.ogg")
const MASTER_BUS := &"Master"
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"

var total_volume: float = DEFAULT_VOLUME
var music_volume: float = DEFAULT_VOLUME
var sfx_volume: float = DEFAULT_VOLUME

var _players: Array[AudioStreamPlayer] = []
var _active_player: AudioStreamPlayer
var _current_key := ""
var _current_stream: AudioStream
var _current_gain_db := 0.0
var _music_stack: Array[Dictionary] = []
var _saved_positions: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_bus(MUSIC_BUS)
	_ensure_audio_bus(SFX_BUS)
	_load_settings()
	_apply_volumes()
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "MusicPlayer%d" % (index + 1)
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.bus = MUSIC_BUS
		add_child(player)
		_players.append(player)
	_active_player = _players[0]


func start_background_music() -> void:
	if _current_key == "background":
		return
	if _current_key == "":
		_play_track("background", BACKGROUND_STREAM, true, 0.0, 0.0)


func push_music(key: String, stream: AudioStream, loop := false, start_position := 0.0, gain_db := 0.0) -> void:
	if key == "" or stream == null or _current_key == key:
		return
	if _current_key != "" and _active_player != null:
		var saved_position := _save_current_position()
		_music_stack.append({
			"key": _current_key,
			"stream": _current_stream,
			"loop": _stream_is_looping(_current_stream),
			"position": saved_position,
			"gain_db": _current_gain_db,
		})
	_play_track(key, stream, loop, start_position, gain_db)


func switch_music(key: String, stream: AudioStream, loop := false, start_position := 0.0, gain_db := 0.0) -> void:
	if key == "" or stream == null:
		return
	if _current_key == key and _current_stream == stream:
		return
	_play_track(key, stream, loop, start_position, gain_db)


func pop_music(key: String) -> void:
	if key == "" or _current_key != key:
		return
	_save_current_position()
	if _music_stack.is_empty():
		_fade_out_current()
		_current_key = ""
		_current_stream = null
		_current_gain_db = 0.0
		return
	var previous: Dictionary = _music_stack.pop_back()
	_play_track(
		str(previous.get("key", "")),
		previous.get("stream") as AudioStream,
		bool(previous.get("loop", false)),
		float(previous.get("position", 0.0)),
		float(previous.get("gain_db", 0.0))
	)


func pause_current_music() -> void:
	if _current_key == "" or _active_player == null:
		return
	var saved_position := _save_current_position()
	_music_stack.append({
		"key": _current_key,
		"stream": _current_stream,
		"loop": _stream_is_looping(_current_stream),
		"position": saved_position,
		"gain_db": _current_gain_db,
	})
	_fade_out_current()
	_current_key = ""
	_current_stream = null
	_current_gain_db = 0.0


func return_to_music(key: String) -> void:
	if key == "" or _current_key == key:
		return
	_save_current_position()
	var target_index := -1
	for index in _music_stack.size():
		if str(_music_stack[index].get("key", "")) == key:
			target_index = index
	if target_index < 0:
		return
	var target: Dictionary = _music_stack[target_index]
	_music_stack.resize(target_index)
	_play_track(
		key,
		target.get("stream") as AudioStream,
		bool(target.get("loop", false)),
		float(target.get("position", 0.0)),
		float(target.get("gain_db", 0.0))
	)


func fade_out_current_music() -> void:
	_fade_out_current()


func clear_music(key: String) -> void:
	if _current_key == key:
		pop_music(key)
	else:
		for index in range(_music_stack.size() - 1, -1, -1):
			if str(_music_stack[index].get("key", "")) == key:
				_music_stack.remove_at(index)
	_saved_positions.erase(key)


func stop_all_music(fade_out := false) -> void:
	if fade_out and _active_player != null and _active_player.playing:
		_fade_out_current()
	_music_stack.clear()
	_saved_positions.clear()
	_current_key = ""
	_current_stream = null
	_current_gain_db = 0.0
	for player in _players:
		if not fade_out or player != _active_player:
			player.stop()


func set_total_volume(percent: float) -> void:
	total_volume = clampf(percent, 0.0, 100.0)
	_apply_bus_volume(MASTER_BUS, total_volume)
	_save_settings()


func get_total_volume() -> float:
	return total_volume


func set_music_volume(percent: float) -> void:
	music_volume = clampf(percent, 0.0, 100.0)
	_apply_bus_volume(MUSIC_BUS, music_volume)
	_save_settings()


func get_music_volume() -> float:
	return music_volume


func set_sfx_volume(percent: float) -> void:
	sfx_volume = clampf(percent, 0.0, 100.0)
	_apply_sfx_volume()
	_save_settings()


func get_sfx_volume() -> float:
	return sfx_volume


func set_game_volume(percent: float) -> void:
	set_total_volume(percent)


func get_game_volume() -> float:
	return get_total_volume()


func get_current_music_key() -> String:
	return _current_key


func wait_until_music_finished(key: String) -> void:
	if key == "" or _current_key != key or _active_player == null or not _active_player.playing:
		return
	await _active_player.finished


func _play_track(key: String, stream: AudioStream, loop: bool, start_position: float, gain_db: float) -> void:
	if stream == null:
		return
	var old_player := _active_player
	var new_player := _players[1] if _active_player == _players[0] else _players[0]
	_active_player = new_player
	_current_key = key
	_current_stream = stream
	_current_gain_db = gain_db
	_configure_stream(stream, loop)
	new_player.stop()
	new_player.stream = stream
	new_player.volume_db = -80.0
	new_player.play(maxf(start_position, 0.0))
	var fade_in := create_tween()
	fade_in.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_in.tween_property(new_player, "volume_db", gain_db, FADE_DURATION)
	if old_player != null and old_player.playing:
		var fade_out := create_tween()
		fade_out.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade_out.tween_property(old_player, "volume_db", -80.0, FADE_DURATION)
		fade_out.tween_callback(old_player.stop)


func _fade_out_current() -> void:
	if _active_player == null or not _active_player.playing:
		return
	var player := _active_player
	var fade := create_tween()
	fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.tween_property(player, "volume_db", -80.0, FADE_DURATION)
	fade.tween_callback(player.stop)


func _save_current_position() -> float:
	if _active_player == null or _current_key == "":
		return 0.0
	var position := _active_player.get_playback_position()
	_saved_positions[_current_key] = position
	return position


func _configure_stream(stream: AudioStream, loop: bool) -> void:
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = loop
	var mp3 := stream as AudioStreamMP3
	if mp3 != null:
		mp3.loop = loop


func _stream_is_looping(stream: AudioStream) -> bool:
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		return ogg.loop
	var mp3 := stream as AudioStreamMP3
	return mp3 != null and mp3.loop


func _ensure_audio_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, MASTER_BUS)


func _apply_volumes() -> void:
	_apply_bus_volume(MASTER_BUS, total_volume)
	_apply_bus_volume(MUSIC_BUS, music_volume)
	_apply_sfx_volume()


func _apply_sfx_volume() -> void:
	# 保留设置界面的 0-100 刻度，但让滑杆 60 对应旧刻度 20 的实际响度。
	var effective_volume := sfx_volume * DEFAULT_SFX_EFFECTIVE_VOLUME / DEFAULT_VOLUME
	_apply_bus_volume(SFX_BUS, effective_volume)


func _apply_bus_volume(bus_name: StringName, percent: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	if percent <= 0.0:
		AudioServer.set_bus_volume_db(bus, -80.0)
	elif percent <= DEFAULT_VOLUME:
		AudioServer.set_bus_volume_db(bus, linear_to_db(percent / DEFAULT_VOLUME))
	else:
		AudioServer.set_bus_volume_db(bus, lerpf(0.0, 6.0, (percent - DEFAULT_VOLUME) / (100.0 - DEFAULT_VOLUME)))


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var legacy_volume := float(config.get_value(SETTINGS_SECTION, "game_volume", DEFAULT_VOLUME))
		total_volume = clampf(float(config.get_value(SETTINGS_SECTION, "total_volume", legacy_volume)), 0.0, 100.0)
		music_volume = clampf(float(config.get_value(SETTINGS_SECTION, "music_volume", DEFAULT_VOLUME)), 0.0, 100.0)
		sfx_volume = clampf(float(config.get_value(SETTINGS_SECTION, "sfx_volume", DEFAULT_VOLUME)), 0.0, 100.0)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION, "game_volume", total_volume)
	config.set_value(SETTINGS_SECTION, "total_volume", total_volume)
	config.set_value(SETTINGS_SECTION, "music_volume", music_volume)
	config.set_value(SETTINGS_SECTION, "sfx_volume", sfx_volume)
	config.save(SETTINGS_PATH)
