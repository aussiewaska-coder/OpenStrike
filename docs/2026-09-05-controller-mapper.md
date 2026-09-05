# Graphical controller mapping

Settings → Controller provides an interactive gamepad diagram and an action
selector. Choose an action, select Detect input, then press a button, squeeze a
trigger or move a stick. Detection previews the input and any other actions
sharing it. Save applies the binding; Cancel preserves the previous assignment.
Tapping a button or stick direction in the diagram also previews a binding.
Restore default layout has its own confirmation.

The diagram highlights the selected binding and live controller input. Landscape
layouts show the diagram beside the editor; narrow layouts scroll vertically.
Settings tabs and Resume remain available. Standard menu navigation is separate
from the custom flight layout, so remapping flight does not remove menu access.

One portable custom layout is stored in `user://controller_bindings.cfg` and
reloaded at startup. It applies to the active controller. The binding table is
also the source of defaults. Invalid saved entries fall back to their defaults;
failed saves leave the previous active layout in place.

Flight, look, throttle modifier, rudder, vectoring, weapons, camera and target
controls read these bindings, including controls that previously polled fixed
physical axes or buttons. Trigger normalization and flight stick deadzones are
preserved. Bindings can use a button or a signed axis direction. Existing
tap/hold and aircraft-specific action meanings remain intact.

While the mapper is open, flight action notifications are suppressed. Capture
uses the active device, waits past the initiating press, requires neutral axes
before a substantial movement, and handles signed trigger resting values.
Captured input is consumed through release so B does not close Settings and the
detected button cannot also activate Save. Disconnect cancels detection.

The mapper regression test exercises real settings and raw input dispatch,
persistence, changed flight controls, cancellation, shared bindings, save errors,
malformed profiles, controller disconnection and three viewport sizes. Its
optional visual output renders the production UI with Compatibility.

Validation: 72/72 headless tests passed. The mapper regression was rerun after
the final capture-release guard change and passed. Production settings were
rendered and inspected at 640×360, 360×640 and 1280×720. Hardware Bluetooth
input was not exercised; controller events were simulated through input dispatch.
