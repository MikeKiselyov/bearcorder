"""Checks an "open-onboarding" result: the window frame lies inside the visible part of the screen.

    python3 scripts/window-fits.py "frame=x,y,w,h visible=x,y,w,h"   # exit 0 when it fits
"""
import sys


def numbers(result, name):
    for part in result.split():
        if part.startswith(name + "="):
            values = []
            for value in part[len(name) + 1:].split(","):
                values.append(int(value))
            return values
    return None


result = sys.argv[1]
frame = numbers(result, "frame")
visible = numbers(result, "visible")
if frame is None or visible is None:
    sys.exit(1)
frame_x, frame_y, frame_width, frame_height = frame
visible_x, visible_y, visible_width, visible_height = visible
fits = True
if frame_x < visible_x or frame_y < visible_y:
    fits = False
if frame_x + frame_width > visible_x + visible_width:
    fits = False
if frame_y + frame_height > visible_y + visible_height:
    fits = False
if not fits:
    sys.exit(1)
