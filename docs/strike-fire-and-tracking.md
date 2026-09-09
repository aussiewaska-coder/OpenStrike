# Sustained strike fire and persistent target view

Bomb, guided-bomb, missile and rocket surface impacts use the same sustained
fire pool. Destroyed ground targets burn, and severely damaged buildings also
ignite after cannon hits. Hostile missile surface impacts now use that pool.
Destroyed enemy aircraft leave falling fire sources that settle on terrain;
the player's moving wreck keeps one emitter rather than dropping stationary
fires along its path. Water surface impacts retain their existing splash path.

Smoke uses a shared procedurally generated shaded-lobe sprite, expanded and
rotated through a world-space CPU particle system. It is a volumetric-looking
billboard approximation, not ray-marched fluid smoke. Smoke emission builds
in strength, rises with buoyancy, drifts with the weather wind and independent
site turbulence, then thins as the fire cools. Particle lifetime, size, rotation
and acceleration vary. The growth curve now allows values above 1, fixing the
old clamped expansion. Flames flicker and lean with the wind.

Each pool remains capped at 16 sites, with 56 smoke and 24 fire particles per
site (previously 96 and 40). Particles simulate at 20 Hz. Ground sites emit for
60 seconds and larger building sites for 100, with lingering smoke fading over
its 24-second lifetime. Pool reuse bounds sustained cost; target-phone frame
time and transparency overdraw still require measurement.

Selecting another jet or helicopter view preserves existing target tracking;
the new camera pose is aimed at the same live contact. Manual look and explicit
tracking release retain their existing behaviour. Regression coverage exercises
all jet camera modes, hostile/player surface impacts, falling wrecks and fire
pool lifecycle. The render fixture captures production emitters at 3, 15 and
40 seconds using particle preprocessing to avoid shader-startup clock skew.
These are simulated-age previews; turbulence during preprocessing is held at
the sampled site's current settings rather than replayed frame by frame.


## Explosion and smoke diffusion update

Explosion fire sprites are larger and eject faster, with a wider light flash.
Every explosion starts one expanding, fading spherical pressure-wave shell;
eight reusable shells cap concurrent cost. The shell expands to 180 m over
1.4 seconds, clipped by ordinary scene depth. Rocket surface hits now receive
the same explosion presentation as bombs and missiles.

Smoke shading blends from dark, shaped puffs near the source to soft low-opacity
haze over 60–380 m of rise, then fades away over 400–950 m. Height is relative
to each source, so elevated terrain does not prematurely dissolve the smoke.
Particle-age opacity also drops earlier. This retains dense smoke at the flame
while removing the rounded upper-puff silhouettes. The shader uses two small
shared textures, with unchanged particle counts and no volume ray march.

Lifecycle, routing and shockwave pool tests pass; real Compatibility screenshots
exercise both shaders. Device frame rate remains unmeasured.
