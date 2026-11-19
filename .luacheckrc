std = "luajit"
max_line_length = 140
globals = { "G_reader_settings" }
read_globals = { "G_defaults" }
files["spec"] = { max_line_length = false }
files["spec/stubs"] = { unused_args = false, globals = { "G_reader_settings", "G_defaults" } }
