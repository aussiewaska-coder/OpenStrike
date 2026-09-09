# Pitch and roll after stick release

The device report was uncontrolled pitch/roll and aircraft flying sideways.
The captured F-22 telemetry showed a neutral climbing bank deepening, along
with substantial frame stalls. Replaying the production controller at 60 Hz
reproduced two handling defects independently of rendering:

- A half-second full roll continued another 12.9 degrees after release.
  A half-stick pitch correction continued another 2.7 degrees.
- A neutral 30-degree bank at 20 degrees nose-up deepened to 38.7 degrees
  over ten seconds. The descending case relaxed to 24.7 degrees.

Pitch and roll now settle more quickly when their stick axis returns to
neutral. Engagement retains its existing response. The same replay now
continues 3.3 degrees in full roll and 0.7 degrees in half-stick pitch.

Automatic turn coordination now resolves its heading rotation into all three
body axes at the current nose elevation. Previously it used the level-flight
pitch/yaw terms with no roll component, which changed bank during climbs and
descents. The ten-second cases now hold their selected bank within 0.13 degrees
and pitch within 0.17 degrees. This is bank hold, with no automatic return to
wings level. The sine/cosine projection remains finite through vertical flight.

`tests/jet_stick_release_test.gd` exercises the production gamepad routing and
controller integration for both roll/pitch directions and neutral bank holds
in climbs, level flight and descents. It failed before the fixes and passed
afterward. The complete headless regression suite passed: 87/87 tests.

Android debug export completed; APK signature, ZIP integrity, ARM64 engine
library and packaged controller/assist scripts were verified. Build:
`OpenStrike-flight-control-fix-2026-09-05.apk`. The exporter also emitted the
project's missing-icon diagnostic and could not launch its ADB child; neither
prevented APK creation. Installation and flight testing were not performed.

The sideways report remains unresolved. Captured sideslip reached 17.9 degrees
during combined roll/pitch manoeuvres. That does not establish whether the
user meant their own aircraft or the surrounding jets, or whether the visible
problem was attitude versus travel or model orientation. A device screenshot
request timed out. No mesh orientation or sideslip coefficients were changed.

Device controller feel still needs verification on the new build. Frame stalls
are separate: the first 120 telemetry samples ranged from 16 to 100 FPS, with
median processing time 19.3 ms, p90 67.9 ms and a maximum of 134.0 ms.
