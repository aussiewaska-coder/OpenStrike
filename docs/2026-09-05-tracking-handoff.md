# Manual look after target tracking

Moving the stick stopped camera tracking but resumed the old manual look angles.
External views also immediately aimed back at the aircraft. A regression through
the production camera updates reproduced first-frame orientation jumps of
46–149 degrees, including targets behind and above the normal cockpit limits.

Manual takeover now captures the complete displayed orientation relative to the
current cockpit or external camera reference. Stick movement rotates that pose
directly. The old manual angles and external orbit position remain fixed during
takeover, so the view continues from the tracked direction and the camera boom
keeps its distance. Neutral input holds the new view. Weapon lock is retained;
only camera tracking stops. Post-deadzone stick movement takes over immediately,
without the former extra 0.25 threshold.

R3 in the jet smoothly recenters the taken-over view. Interrupting a tracked-view
return captures its current displayed orientation too, including in external
views. Explicit view changes clear takeover, and starting target tracking again
returns camera ownership to the tracker. Apache cockpit and external aim use the
same pose-preserving handoff.

The regression exercises banked aircraft, all four jet views, gentle input,
targets beyond normal look limits, continued input, neutral hold, retained weapon
lock, external distance, R3, interrupted recentering and all Apache views. The
previous large first-frame jumps become approximately two degrees for the tested
stick input at 60 Hz. Validation uses camera transforms and simulated stick input;
physical controller feel still needs device use.

The full headless regression suite passed: 74/74 tests. The Android debug export
passed signature and archive verification and was copied to Android Downloads.
