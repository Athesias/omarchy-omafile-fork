# Simulates a mouse drag through a uinput virtual mouse (python-evdev).
# Usage: python3 tests/drag_sim.py FROM_X FROM_Y TO_X TO_Y [midway-screenshot.png]
# Coordinates are Hyprland layout pixels; the cursor is placed with hyprctl.
import subprocess, sys, time
from evdev import UInput, ecodes as e

x0, y0, x1, y1 = map(int, sys.argv[1:5])
shot = sys.argv[5] if len(sys.argv) > 5 else None
ui = UInput({e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT], e.EV_REL: [e.REL_X, e.REL_Y]}, name="omafile-test-mouse")
time.sleep(1.0)

def warp(x, y):
    subprocess.run(["hyprctl", "dispatch", "hl.dsp.cursor.move({ x = %d, y = %d })" % (x, y)], capture_output=True)

def rel(dx, dy):
    ui.write(e.EV_REL, e.REL_X, dx); ui.write(e.EV_REL, e.REL_Y, dy); ui.syn()

warp(x0, y0); time.sleep(0.3)
rel(1, 0); rel(-1, 0); time.sleep(0.2)
ui.write(e.EV_KEY, e.BTN_LEFT, 1); ui.syn(); time.sleep(0.25)
steps = 30
for i in range(steps):
    tx = x0 + (x1 - x0) * (i + 1) // steps
    ty = y0 + (y1 - y0) * (i + 1) // steps
    warp(tx, ty); rel(1, 0); rel(-1, 0)
    time.sleep(0.03)
    if shot and i == steps // 2:
        subprocess.run(["grim", "-g", "%d,%d 500x200" % (tx - 250, ty - 100), shot])
time.sleep(0.4)
ui.write(e.EV_KEY, e.BTN_LEFT, 0); ui.syn(); time.sleep(0.5)
ui.close()
