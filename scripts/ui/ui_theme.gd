class_name UiTheme
## Caper City look: dusk asphalt panels, coral = you / call to action, teal = spectating & info,
## yellow = money. Built in code so there are no binary theme files to merge.

const BG := Color("#15171C")
const PANEL := Color(0.082, 0.09, 0.11, 0.94)
const PANEL_2 := Color("#1E2128")
const BORDER := Color("#2C3038")
const BORDER_2 := Color("#3A3F49")
const TEXT := Color("#F2EEE6")
const MUTED := Color("#B5B9C2")
const CORAL := Color("#FF5D4F")
const CORAL_DARK := Color("#1B1210")
const TEAL := Color("#35D0BA")
const TEAL_DARK := Color("#0E1A1A")
const YELLOW := Color("#F2C230")
const RED_SOFT := Color("#FF9C90")

## Phone layout: set once at startup by main.gd. The HUD reads it to tighten its panels.
static var compact := false


## Phones get the compact layout; tablets and desktops keep the full one. Override with
## ?mobile=1 / ?desktop=1 in the page URL, or --mobile / --desktop after "--" on the command line.
## The character model a player appears as: the avatar they picked, or one by player id until then.
static func look_of(p: Dictionary) -> String:
	var a: String = p.get("avatar", "")
	if a != "":
		return a
	return Balance.AVATARS[int(p.get("id", 0)) % Balance.AVATARS.size()].id


static func detect_compact() -> bool:
	var args := OS.get_cmdline_user_args()
	if "--mobile" in args:
		return true
	if "--desktop" in args:
		return false
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("location.search", true))
		if "mobile=1" in q:
			return true
		if "desktop=1" in q:
			return false
		if OS.has_feature("web_android") or OS.has_feature("web_ios"):
			return true
		# iPads report themselves as Macs; a small touch screen is still a phone.
		var short_side := float(JavaScriptBridge.eval("Math.min(screen.width, screen.height)", true))
		return DisplayServer.is_touchscreen_available() and short_side > 0 and short_side < 600
	return OS.has_feature("mobile")


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 12, pad: int = 12, border_w: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w if border.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 12, 12))
	t.set_stylebox("panel", "Panel", box(PANEL, BORDER, 12, 12))

	t.set_stylebox("normal", "Button", box(PANEL_2, BORDER_2, 10, 14))
	t.set_stylebox("hover", "Button", box(PANEL_2.lightened(0.08), TEAL, 10, 14))
	t.set_stylebox("pressed", "Button", box(PANEL_2.darkened(0.2), TEAL, 10, 14))
	t.set_stylebox("disabled", "Button", box(Color("#191B20"), BORDER, 10, 14))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), TEAL, 10, 14, 2))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color("#8E939D"))

	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(CORAL, Color(0, 0, 0, 0), 10, 16))
	t.set_stylebox("hover", "PrimaryButton", box(CORAL.lightened(0.1), Color(0, 0, 0, 0), 10, 16))
	t.set_stylebox("pressed", "PrimaryButton", box(CORAL.darkened(0.15), Color(0, 0, 0, 0), 10, 16))
	t.set_stylebox("disabled", "PrimaryButton", box(Color("#5A3330"), Color(0, 0, 0, 0), 10, 16))
	t.set_color("font_color", "PrimaryButton", CORAL_DARK)
	t.set_color("font_hover_color", "PrimaryButton", CORAL_DARK)
	t.set_color("font_pressed_color", "PrimaryButton", CORAL_DARK)
	t.set_color("font_disabled_color", "PrimaryButton", Color("#B08A85"))

	t.set_stylebox("normal", "LineEdit", box(PANEL_2, BORDER_2, 10, 12))
	t.set_stylebox("focus", "LineEdit", box(PANEL_2, TEAL, 10, 12, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color("#7D828C"))

	t.set_stylebox("normal", "OptionButton", box(PANEL_2, BORDER_2, 10, 14))
	t.set_stylebox("hover", "OptionButton", box(PANEL_2.lightened(0.08), TEAL, 10, 14))
	t.set_stylebox("pressed", "OptionButton", box(PANEL_2, TEAL, 10, 14))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	return t


static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, primary: bool = false, min_h: int = 48) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	return b
