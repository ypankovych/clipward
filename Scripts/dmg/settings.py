# dmgbuild settings for the Clipward installer.
# Invoked by Scripts/make-dmg.sh with -D app=<path to .app> -D background=<path to .tiff>.
import os.path

application = defines["app"]  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
badge_icon = None
icon = os.path.join(application, "Contents/Resources/AppIcon.icns")

background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    app_name: (170, 200),
    "Applications": (470, 200),
}
