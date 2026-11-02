extends RefCounted

## Toggleable display / audio prefs surfaced from the mode-menu Settings screen.
## Keep blurbs short - they render under each option button.

const ID_FULLSCREEN := "fullscreen"
const ID_JUICE := "juice"
const ID_BACKDROP := "backdrop"
const ID_THEME := "theme"
const ID_GREETINGS := "greetings"
const ID_MUTE := "mute"
const ID_TOUCH_SCALE := "touch_scale"
const ID_TOUCH_ZONES := "touch_zones"


static func entries(touch_primary: bool) -> Array:
	var rows: Array = [
		{
			"id": ID_JUICE,
			"title": "Juice FX",
			"blurb": "Screen shake, particles, and score popups. Tip: Set OFF on low powered devices.",
		},
		{
			"id": ID_THEME,
			"title": "Color theme",
			"blurb": "Cycle the neon UI palette.",
		},
		{
			"id": ID_BACKDROP,
			"title": "Background",
			"blurb": "Dim lines, bright lines, or starfield horizon. Tip: Change to Dim or Bright Lines on low powered devices.",
		},
		{
			"id": ID_FULLSCREEN,
			"title": "Fullscreen",
			"blurb": "Fill the display or return to a window.",
		},
		{
			"id": ID_GREETINGS,
			"title": "Rank greetings",
			"blurb": "Announce when you climb into the top 10.",
		},
		{
			"id": ID_MUTE,
			"title": "Music",
			"blurb": "Mute or unmute the soundtrack.",
		},
	]
	if touch_primary:
		rows.append({
			"id": ID_TOUCH_SCALE,
			"title": "Button size",
			"blurb": "Scale on-screen controls (1x through 4x).",
		})
		rows.append({
			"id": ID_TOUCH_ZONES,
			"title": "Tap zones",
			"blurb": "Show the upper left/right move zones.",
		})
	return rows
