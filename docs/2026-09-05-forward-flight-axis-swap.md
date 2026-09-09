# Forward flight and swapped pitch/roll controls

Jet controls now follow the requested swapped layout: left-stick left/right
commands pitch (right raises the nose), and up/down commands roll (down rolls
right). This routing happens in the jet controller, so saved bindings still
work and helicopter controls retain their existing layout. Controller setup
labels and the README describe both aircraft's corresponding actions.

The subsequent device trace showed over 33 degrees of sideslip at roughly
55 m/s with the stick centred. A production-controller reproduction retained
31.8 degrees of a 35-degree slip after half a second at that speed, and 28.9
degrees at 175 m/s. Faster rotational settling alone did not address this:
aerodynamic side force and yaw damping still allowed sustained sideways travel.

The flight assist now rotates the horizontal component of body-space velocity
toward the nose with an exponential response. It preserves speed and
body-vertical velocity, leaving lift, climbing, drag, throttle and pitch limits
active. Deliberate rudder fades the direction assist to preserve pedal control;
releasing it restores forward flight promptly. The controller publishes the
corrected angles for the next physics step and telemetry.

The same half-second cases now finish at 0.48 degrees of slip at 55 m/s and
0.09 degrees at 175 m/s. A five-second full roll completes 501.6 degrees, with
maximum slip 0.50 degrees and a minimum nose/travel dot product of 0.999.

Validation: ten relevant tests passed, covering production physical-axis
routing, forward travel, full rolling flight, stick release, rudder and
vectoring, neutral flight and recovery, brakes, controller remapping/input,
the Nighthawk airframe, flight assistance and the aerodynamic control model.
`jet_forward_flight_test.gd` failed on both the mapping and sideways-travel
requirements before the change and passes afterward. An initial test command
also named a nonexistent `controller_bindings_test.gd`; the repository's
actual controller mapper and gamepad tests were run and passed.

On-device feel and rendering still need a flight with the new APK. Frame stalls
remain a separate outstanding issue.

`OpenStrike-forward-swapped-controls-2026-09-05.apk` was exported, verified
with `apksigner`, checked for ZIP integrity and the changed compiled scripts,
and copied to Android Downloads with matching SHA-256 hashes. The build's
Gradle daemon was stopped afterward; its resident memory was about 1.4 GB.
