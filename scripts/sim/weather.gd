extends RefCounted
## Deterministic daily weather. A forecast is a pure function of (day, season) so it
## survives save/load and every test seed. Rendering reads the kind; rules read the
## small modifiers below. Nothing here is punishing: weather colors the day.

const SUNNY := 0
const CLOUDY := 1
const RAIN := 2
const STORM := 3
const WIND := 4
const FOG := 5
const HOT := 6
const SNOW := 7

const NAMES := ["Sunny", "Cloudy", "Light rain", "Thunderstorms", "Windy", "Fog", "Hot", "Snow"]

## Per-season weights for each kind (sunny, cloudy, rain, storm, wind, fog, hot, snow).
const WEIGHTS := [
	[30, 24, 26, 8, 8, 4, 0, 0],      # spring
	[40, 14, 8, 14, 2, 2, 20, 0],     # summer
	[26, 26, 14, 4, 20, 10, 0, 0],    # fall
	[16, 28, 6, 0, 8, 12, 0, 30],     # winter
]


static func for_day(day: int, season: int) -> int:
	var h := int(absi((day * 2654435761 + 40503) % 1000003))
	var roll := h % 100
	var weights: Array = WEIGHTS[clampi(season, 0, 3)]
	for kind in weights.size():
		roll -= int(weights[kind])
		if roll < 0:
			return kind
	return CLOUDY


static func name_of(kind: int) -> String:
	return NAMES[clampi(kind, 0, NAMES.size() - 1)]


## The hour (0-23) a storm is likely to hit, shown in the morning brief.
static func storm_hour(day: int) -> int:
	return 14 + day % 5


static func is_wet(kind: int) -> bool:
	return kind in [RAIN, STORM, SNOW]


## Share of pedestrians, kids and gardeners who go out.
static func outdoor_factor(kind: int) -> float:
	match kind:
		STORM:
			return 0.2
		RAIN:
			return 0.5
		SNOW:
			return 0.4
		HOT:
			return 0.7
		FOG, WIND:
			return 0.8
	return 1.0


## Evidence photo quality lost to the conditions (percentage points).
static func photo_penalty(kind: int) -> int:
	match kind:
		STORM:
			return 14
		RAIN, SNOW:
			return 8
		FOG:
			return 12
	return 0


static func brief_line(kind: int, day: int) -> String:
	if kind == STORM:
		return "Thunderstorms likely after %d PM." % (storm_hour(day) - 12)
	return "%s today." % name_of(kind)
