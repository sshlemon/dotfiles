-- DMS user keybind overrides (edit via Control Center or dms; do not remove this header)

hl.unbind("ALT + CTRL + L")
hl.bind("ALT + CTRL + L", hl.dsp.exec_cmd("dms ipc call lock lock"), { description = "dms ipc call lock lock" })
hl.unbind("SUPER + D")
hl.bind(
	"SUPER + D",
	hl.dsp.exec_cmd("dms ipc call spotlight toggle"),
	{ description = "dms ipc call spotlight toggle" }
)
hl.unbind("SUPER + Return")
hl.bind("SUPER + Return", hl.dsp.exec_cmd("ghostty"), { description = "ghostty" })
hl.unbind("Print")
hl.unbind("SUPER + ALT + L")
hl.unbind("SUPER + T")
hl.unbind("SUPER + space")
hl.unbind("SUPER + S")
hl.bind("SUPER + S", hl.dsp.exec_cmd("dms screenshot"), { description = "dms screenshot" })
hl.bind("CTRL + SHIFT + A", hl.dsp.global("org.keepassxc.KeePassXC:autotype"))
