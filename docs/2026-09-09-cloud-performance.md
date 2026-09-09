# Cloud performance and combat pacing — 9 September 2026

The installed volumetric build showed vertically stretched cloud banks with
fine striped edges. A device screenshot and two short telemetry captures are
saved in `build/validation/cloud-regression/`.

After discarding the first three samples, the median frame rate was 25 FPS
with normal clear-weather coverage near 1,500 m altitude and 38 FPS after temporarily setting
coverage to zero. Coverage was restored to 0.5 afterwards. This was a moving
flight, not a fixed-camera GPU benchmark. The process-time monitor did not
track the FPS change consistently, so it is not used as a GPU timing result.

The baseline pass traced five sun-shadow density samples at every one of its
96 view steps. The revised pass retains the view detail but caches two-sample
sun lighting at sparse anchors and interpolates between them. Dense rays use
roughly four times fewer density evaluations; actual savings depend on empty
space and early termination. No improved device FPS is claimed before the
new APK is installed and measured.

Fixed sampling alone made little visual difference at low resolution. Reducing
the view count to 32 exposed visible marching bands, so that setting was not
adopted. The final changes strengthen the true 3D billow field, lower the tops of thin
coverage patches to form cloud shoulders, soften extinction, clip sun
integration to the cloud band, and interpolate lighting.
A distinct low-discrepancy phase at each view step avoids coherent ray offsets.
Mobile 3D resolution is scaled to 0.75, reducing its pixel count by about 44%
while keeping the HUD at native resolution. A local rendered comparison at
the cloud base and the foreground-depth regression are the
feedback loop. Mobile appearance still requires checking on the updated APK.

Combat pacing also changed at the user's request:

- One or two jets per encounter; first encounter after 20 seconds.
- 30–45 seconds between cleared waves.
- One launcher at each of six sites, instead of four (6 total rather than 24).
- Only one eligible attacker can acquire the player at a time. Cooling-down
  sources cannot drive lock warnings.
- 30 seconds of initial missile grace and 20 seconds after a missile retires.
  The existing one-active-missile limit remains.

A regression with 24 eligible SAMs failed on the previous code because many
could acquire simultaneously. It passes with the shared acquisition limit;
this remains a stress test even though normal spawning now creates six sites.

For the next device comparison, telemetry supports `cloud_enabled`,
`cloud_steps`, `cloud_shadow_steps`, and `render_scale_3d` and reports those values alongside FPS.
Use the same stationary view, weather, and terrain loading state for each
sample window. Keep screenshot requests outside the timing window.

The GPU regression with a uniform thin coverage map fails against the old
shader: cloud reaches a 2,000 m camera despite the patch being too weak to
form a tall cloud. It passes against the new shader. The same test verifies
opaque foreground clipping at the mobile 0.75 render scale.


## Follow-up: persistent columns and horizontal bands

The economy APK did not resolve the user's visual artifacts. A flat-lighting
reference retained column silhouettes, while replacing the cached lighting
reduced broad shading bands. Cellular-noise-only boundaries still produced a
sharp seam in the 1500 m close-up and were rejected.

The final density boundary uses four neighboring finite ellipsoidal puffs,
with varied centres and dimensions and cellular noise for edge erosion.
Coverage modulates opacity. The layer is now 1600–2000 m; clear coverage is
0.65. Sun transmission uses two samples at each occupied view sample, without
the previous lighting cache. The 96 view samples, 0.75 mobile render scale,
and reduced enemy/lock-on settings remain. Removing the cache increases shadow
work per occupied sample; no improved device FPS is claimed.

Softpipe Compatibility captures at 1500 m and above the layer show rounded
boundaries without the earlier sharp vertical seam. These small software
renders do not establish phone image quality or performance. Captures and the
passing foreground-clipping render log are in `build/validation/cloud-banding/`.
Weather state, weather runtime and main-scene dogfight runtime checks passed.
The render regression now uses a controlled erosion texture for foreground
clipping; its above-layer check validates finite extent, not cloud morphology.
The previous sparse-coverage pillar assertion is not treated as evidence that
these reported artifacts are solved.

The shared environment resource keeps weather fixtures from loading aircraft
and terrain assets. Waiting for asynchronous texture generation fixes the
runtime test's teardown resource warnings. Final isolated captures exited
without texture-leak diagnostics. Device telemetry was unavailable during this
follow-up, so an on-device screenshot and FPS comparison remain outstanding.


## Follow-up: fewer, larger clouds and lower distant cost

The user liked the rounded version but reported frame cost and repetitive,
flattened clouds. The next version increases candidate spacing from 850 to
1900 m, offsets centres much more, leaves deterministic empty cells, varies
both axes and adds an offset raised crown. The 1400–2200 m band permits fuller
vertical profiles; opacity and extinction are increased for denser interiors.
Finite puff support remains smaller than the neighborhood boundary.

Rendering now stops at 12 km (was 30 km), fades out from 6.6 km, and drops
erosion and traced lighting between 2.5 and 5 km. Nearby lighting uses one
shadow sample instead of two. A 48-sample trial showed distracting grain in
the close-up, so the final budget is 64 view samples, with quadratic interval
spacing that concentrates samples near the camera. These are reductions in
shader work, not a measured phone FPS claim. Mobile resolution and reduced
enemy settings are unchanged.

The weather state/runtime tests and Compatibility foreground-depth render
check pass. Small software-rendered screenshots check distribution and shape;
on-device FPS and motion quality still need verification.

The final low-resolution close-up retains visible stochastic grain despite
the 64-sample refinement; motion stability is not established by these stills.


## Follow-up: softer economy clouds with alternating density

The user still reported column-like forms and requested another quality reduction.
Removed raised crowns and noise erosion, lowered the vertical radii, widened the
soft density boundary and reduced extinction. Each cloud receives a stable thin
or dense opacity with small variation; density changes are spatial, not animated
flicker. Default lighting now uses height only, with zero shadow rays. View work
is capped at 48 intervals over 8 km, fading from 4.4 km. The unused 3D noise
texture and its asynchronous generation were removed. Phone FPS remains unmeasured.


## Follow-up: taller connected banks and noon horizon

The user requested more height and connected banks while retaining the economy
renderer. Candidate spacing is now 1500 m, occupancy is higher, radii are wider,
and vertical half-height varies from 256 to 368 m. Overlaps combine smoothly
instead of selecting only the strongest puff. Thin/dense per-cloud variation
remains. Maximum radius plus displacement stays below one cell, so the same
four-candidate neighborhood remains valid. View/shadow budgets are unchanged.

The reported noon horizon cut also matches the saved above-layer view: the
lower sky darkened rapidly immediately beneath the horizon while distant
terrain was fogged pale. The sky now keeps a broad pale haze below the horizon,
then transitions to ground colour farther down. The upper sky gradient also
spreads across a broader elevation range. This changes sky colour only and
adds no rendering pass. Phone appearance and frame rate require verification.


## Follow-up: independent cloud altitude and thickness

Previously cloud centres varied only 32 m, giving banks an almost level top.
The density field now uses a gradual bank-scale altitude change plus independent
per-cloud offsets; thickness varies separately from 240 to 736 m. The integration
and weather envelope expands to 1000–2600 m, with each puff contained inside it.
The shared weather altitude estimate remains approximate; it does not sample
individual puff density. Rain taper follows the expanded envelope.

The 48-view-sample / 8 km limit, no-shadow-ray lighting, mixed opacity, connected
banks and noon haze remain. The wider envelope can increase work on some camera
angles despite the unchanged sample cap; no phone FPS improvement is claimed.


## Follow-up: layered cloud types

Added a thin cirrus background sheet at 6.5 km (two texture reads, no extra
volume march), plus storm-only rising cloud bodies and anvils below 5.6 km.
The existing cumulus banks, variable altitude and density, 48 view intervals,
8 km volume range and zero default shadow rays remain. Storm development is
smoothly driven by coverage between 0.95 and 1.0, wired to the existing Weather
control in Options → Display. The menu description now mentions storm towers.

Daylight and weather tests pass. The GPU depth regression additionally compares
a 3 km view in clear and storm conditions and confirms that storm towers extend
above the low bank. Cirrus has background-only compositing and no fly-through
extinction; weather telemetry and rain retain the lower-bank approximation.
No phone performance measurement has been made for these layers.
