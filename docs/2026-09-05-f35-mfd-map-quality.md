# F-35 live cockpit map and low-altitude imagery

The F-35's right-hand panoramic-display area now carries a live tactical map
and radar scope. Its geometry is aligned to the four measured corners of the
imported cockpit panel, inset inside the bezel and offset 2.5 mm toward the
pilot. The original left-hand instruments remain visible. Only the F-35 opts
into this model-specific mounting; the F-22/F-18 cockpits and F-117 nose view
retain their existing behavior.

A 512×416 SubViewport renders the display at 15 Hz in cockpit view. It stops
rendering and animating in external views. Terrain contours use the shared
heightfield, while contacts, lock and range use the same tracker state as the
corner radar. Aircraft heading rotates the terrain and contacts together; the
ownship marker always points upward. The north marker rotates independently.
Phosphor halos, a sweep and scanlines are drawn into the instrument texture,
so the lit display works in Android Compatibility without post-process bloom.
Tapping the projected physical display cycles the existing radar range. Other
taps still reach target selection. The corner radar returns in external views.

The tactical map shader gained an optional heading rotation, defaulting to zero
for the existing full-screen north-up tactical map.

## Ground resolution regression

Live F-35 telemetry showed BALANCED, compression unavailable, a 2,500 m chunk,
2,048 px directly underneath, no pending requests and zero tile failures.
The uncompressed-memory fallback capped every quality setting at 2,048 px,
which disabled the intended low-altitude detail tier. Cache keys already include
requested dimensions, so deleting the cache would simply reload the capped tile.

BALANCED and QUALITY now retain one 4,096 px near tile below 300 m AGL and five
2,048 px surrounding tiles. Their resident pixel count is nine 2,048-equivalents,
below the previous ten-tile budget. PERFORMANCE keeps its former cap. This is
a resident-memory bound; image decoding and uploads still have transient costs.
The existing speed and altitude hysteresis remain in place.

A fresh request to the configured Queensland ImageServer returned a valid JPEG
header with the requested 4,096×3,614 dimensions (3,858,519 bytes). Across a 2.5 km
chunk that is about 0.61–0.69 m per pixel, twice the linear resolution previously
selected on the device. The sharper request has its own cache entry.

Validation: runtime tests cover the physical display, four cardinal headings,
map/contact alignment, range tapping, renderer shutdown outside cockpit,
material isolation, cockpit positions, aircraft switching, tactical map and
labels, and terrain detail/memory policy. tools/check_f35_mfd.gd renders the
actual F-35 cockpit by day and night, plus a 90-degree heading change. Its
synthetic terrain/contact fixture makes the visual check independent of HTTP.
Screenshots are /tmp/f35-mfd-*.png and /tmp/f35-scope-*.png.

## Phone touch and POV tracking

Tapping the main phone view selects the contact or world point beneath the
finger and immediately starts the same smoothed POV tracking as R1. Touch
selection uses the touch ray, not the centre reticle. Camera initialization is
shared with the R1 path; weapons retain the same lock. Recenter still releases
head tracking while preserving weapon lock, and manual look takes over through
the existing handoff. Tapping the cockpit MFD remains radar range control.

The production phone-touch regression includes a centre contact and a separate
off-centre contact, verifies selection beneath the finger, runs camera tracking
to convergence, and checks recenter preserves the lock. Existing point tracking,
manual handoff and destroyed-target tests cover the shared tracking lifecycle.
