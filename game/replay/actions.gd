extends RefCounted

## Abstract gameplay actions shared by keyboard, touch, and replay playback.

const LEFT_ON := "left_on"
const LEFT_OFF := "left_off"
const RIGHT_ON := "right_on"
const RIGHT_OFF := "right_off"
const SOFT_ON := "soft_on"
const SOFT_OFF := "soft_off"
const ROT := "rot"
const CCW := "ccw"
const DROP := "drop"
const HOLD := "hold"
## One-column moves that do not engage DAS (touch zone nudges).
const NUDGE_LEFT := "nudge_left"
const NUDGE_RIGHT := "nudge_right"

const ALL := [
	LEFT_ON,
	LEFT_OFF,
	RIGHT_ON,
	RIGHT_OFF,
	SOFT_ON,
	SOFT_OFF,
	ROT,
	CCW,
	DROP,
	HOLD,
	NUDGE_LEFT,
	NUDGE_RIGHT,
]


static func is_known(action: String) -> bool:
	return action in ALL
