# Left-stick axes and nose camera

The requested layout now routes left-stick X to roll and Y to pitch: right
banks right, forward lowers the nose, and pulling back raises it. Controller
binding labels and flight regressions use this same layout.

Both jets now use a first-person camera 0.35 m ahead of their forwardmost model
bounds. The camera follows the interpolated aircraft position and attitude,
without the old cockpit panel tilt, head bob or engine/brake vibration. The
view label is NOSE VIEW. HUD, manual look and target tracking remain available.
The shared cockpit-transform method names remain as the first-person interface.

Bounds are transformed into aircraft coordinates before enclosing them in an
AABB, avoiding inflated measurements when the aircraft is already banked or
turned during model replacement. The cockpit-seat measurement code is removed.

Validation:

- The requested axis and nose-placement assertions failed before the change.
- Eleven relevant test files passed: physical input/forward flight, visual
  runtime/model replacement/nose clearance, stick release, aerodynamic controls,
  camera look under load, camera interpolation, jet runtime, model rigging,
  gun attachment, brake/throttle, and flight sweep.
- Real F-22 and F-117 meshes were rendered from the production nose camera;
  both show an unobstructed runway and horizon. Images are in
  `build/validation/f22-nose-camera.png` and `f117-nose-camera.png`.
- Nose bounds remain stable after changing heading and bank: F-22 lens X
  13.892 m versus hull end 13.542 m; F-117 lens X 6.483 m versus hull end 6.133 m.

Android flight feel still needs confirmation on the phone; automated checks
cover axis routing, forward motion and camera geometry rather than subjective
handling.
