# Flight controls, jet effects and terrain detail

Both rudder triggers retain thrust vectoring during manoeuvres. With a neutral
stick, nearly level wings and a near-horizontal flight path they instead deploy
an airbrake over roughly a third of a second. Drag opposes velocity; neither
throttle nor nose attitude is changed directly. Deliberate manoeuvring restores
vectoring immediately and stows the brake progressively.

Home/Guide defaults to throttle-up. Throttle-down is a separate configurable
action labelled Turbo, initially unassigned because no physical Turbo event has
been observed. Settings → Controller → Detect can bind it. Release holds the
throttle; opposing buttons cancel; menu/map input stays isolated. The right
stick remains available for looking while adjusting throttle. Apache's A manual
aim modifier remains available.

The imported F-22 airframe is partitioned at the trailing wing panels into two
hinged ailerons and the remaining mesh, retaining the original material and all
vertex attributes. Roll moves the panels oppositely; braking raises both.
The source asset and physical airframe transforms remain unchanged. Two small
procedural exhaust meshes animate with actual spooled afterburner power, with
shadowless nozzle lights. Crash suppresses flames and lights. A bounded camera
rotation (under 0.15 degrees total) adds engine/brake vibration only in cockpit
views, after the weapon aim basis is recorded.

Below 300 m AGL, balanced/quality terrain presets keep 4096 px imagery for the
nearest chunk at high speed and the full near-detail budget below 45 m/s. Above
300 m the standard 2048 px tier is used. Hysteresis retains the low-altitude tier
until 330 m and the fast-flight budget until speed falls below 40 m/s. Existing
performance-preset and uncompressed-device caps still apply. Completed fetches
record their actual texture tier, so failed upgrades remain retryable.

Raw controller button edges are retained in a bounded 32-event telemetry ring,
including while Settings is paused. `tools/read_controller.py --seconds 60`
prints observed indices and press/release timestamps; it never guesses the
meaning of a missing Turbo event. Direct device input and the installed game's
telemetry were unavailable during development, so the user's requested
Select → Home → Start → Turbo → Home sequence remains to be captured using the
new APK in the foreground.

Validation: the full 77-test suite passed, followed by the new controller-event
log check and targeted reruns for terrain policy and corrected aileron direction.
A real OpenGL Compatibility renderer under Xvfb compiled and rendered the
plumes, lights and wing panels. Checks cover level-flight drag without roll,
turn-vectoring preservation, persistent button throttle, menu isolation, altitude
and speed detail selection, bounded vibration and crash shutdown. Physical
Bluetooth mapping and on-phone frame rate have not been verified.
