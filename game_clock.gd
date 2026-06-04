extends Node

signal second_changed
signal minute_changed

const START_YEAR := 2005
const START_MONTH := 6
const START_DAY := 6
const START_HOUR := 13
const START_MINUTE := 23
const START_SECOND := 0

@export var seconds_per_real_second := 60.0

var _elapsed_seconds := 0.0
var _last_whole_second := -1
var _last_whole_minute := -1


func _ready() -> void:
	_emit_initial_time()


func _process(delta: float) -> void:
	_elapsed_seconds += delta * seconds_per_real_second
	var whole_second := int(floor(_elapsed_seconds))
	if whole_second == _last_whole_second:
		return
	_last_whole_second = whole_second
	second_changed.emit()

	var whole_minute := int(whole_second / 60)
	if whole_minute != _last_whole_minute:
		_last_whole_minute = whole_minute
		minute_changed.emit()


func get_datetime() -> Dictionary:
	var base := {
		"year": START_YEAR,
		"month": START_MONTH,
		"day": START_DAY,
		"hour": START_HOUR,
		"minute": START_MINUTE,
		"second": START_SECOND,
	}
	return Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_dict(base) + int(floor(_elapsed_seconds)))


func time_string(include_seconds := false) -> String:
	var dt := get_datetime()
	if include_seconds:
		return "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]
	return "%02d:%02d" % [dt.hour, dt.minute]


func date_string() -> String:
	var dt := get_datetime()
	return "%02d.%02d.%04d" % [dt.day, dt.month, dt.year]


func datetime_string(include_seconds := false) -> String:
	return "%s %s" % [date_string(), time_string(include_seconds)]


func hour_12() -> float:
	var dt := get_datetime()
	return fposmod(float(dt.hour), 12.0) + float(dt.minute) / 60.0 + float(dt.second) / 3600.0


func minute() -> float:
	var dt := get_datetime()
	return float(dt.minute) + float(dt.second) / 60.0


func second() -> float:
	var dt := get_datetime()
	return float(dt.second)


func set_time(hour: int, minute_value: int, second_value := 0) -> void:
	var current := get_datetime()
	set_datetime(current.year, current.month, current.day, hour, minute_value, second_value)


func set_time_from_string(value: String) -> bool:
	var parts := value.strip_edges().split(":", false)
	if parts.size() < 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return false
	var hour := int(parts[0])
	var minute_value := int(parts[1])
	var second_value := 0
	if parts.size() >= 3:
		if not parts[2].is_valid_int():
			return false
		second_value = int(parts[2])
	if hour < 0 or hour > 23 or minute_value < 0 or minute_value > 59 or second_value < 0 or second_value > 59:
		return false
	set_time(hour, minute_value, second_value)
	return true


func set_datetime(year: int, month: int, day: int, hour: int, minute_value: int, second_value := 0) -> void:
	var base := {
		"year": START_YEAR,
		"month": START_MONTH,
		"day": START_DAY,
		"hour": START_HOUR,
		"minute": START_MINUTE,
		"second": START_SECOND,
	}
	var target := {
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": minute_value,
		"second": second_value,
	}
	_elapsed_seconds = float(Time.get_unix_time_from_datetime_dict(target) - Time.get_unix_time_from_datetime_dict(base))
	_emit_time_changed()


func _emit_initial_time() -> void:
	_emit_time_changed()


func _emit_time_changed() -> void:
	_last_whole_second = int(floor(_elapsed_seconds))
	_last_whole_minute = int(_last_whole_second / 60)
	second_changed.emit()
	minute_changed.emit()
