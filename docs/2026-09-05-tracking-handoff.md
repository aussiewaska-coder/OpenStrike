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

R3 after a manual glance resumes the retained live target, including targets
selected with R1 or a screen tap and pinned world points. It starts smoothly
from the displayed view and follows the target's current position, even off
screen. A second R3 press while tracking keeps the existing release/recentre
action. Subsequent presses use the existing view-forward/wings-level logic;
retaining a weapon lock alone does not force a return to tracking. If the
target has died or left tracking range, R3 falls back to normal recentring.

Interrupting a tracked-view return captures its current displayed orientation,
including in external views; R3 can then resume the target again. Explicit view
changes clear takeover. Apache cockpit and external aim use the same handoff
and situational R3 target return.

The regression exercises banked aircraft, all four jet views, gentle input,
targets beyond normal look limits, continued input, neutral hold, retained weapon
lock, external distance, R3, interrupted recentering and all Apache views. The
previous large first-frame jumps become approximately two degrees for the tested
stick input at 60 Hz. Validation uses camera transforms and simulated stick input;
physical controller feel still needs device use.

The original handoff change passed the full 74-test headless suite. The
situational R3 update passes six focused suites: manual handoff, R1/touch
tracking, point tracking, camera motion, destroyed-target cleanup and the target
tracker. These cover return to a moving off-screen target, repeated R3 presses,
all jet and Apache views, retained weapon lock and missing-target fallback.
