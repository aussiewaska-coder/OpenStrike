# Settings and F-22 startup

The old settings panel combined every action and all theatres in one scrolling
column, used default small buttons, and did not assign controller focus when
opened. It also left the simulation and globally polled flight actions running.
Later HUD siblings could appear or receive input over the menu.

The replacement has Flight, World, Display and Storage sections. Only section
content scrolls; the section buttons and Resume remain visible. Controls have
large touch targets, a visible focus outline and explicit navigation paths.
Wide screens use two columns; narrow screens use one. Refreshing current values
preserves theatre controls and focus. The fixed F-22 control mode is shown as
unavailable to change; helicopter modes remain selectable.

Opening settings moves it above HUD siblings, focuses Resume and pauses flight.
D-pad and accept input navigate the menu, while main's flight action handlers
ignore menu input. B/Escape and short X close it; X does not also cycle weapons.
Menu pause and controller-disconnect pause are independent: neither closing the
menu nor reconnecting a controller clears the other reason to remain paused.

Startup selects the F-22, activates its controller, parks the Apache and launches
at cruise altitude. The initial camera is the forward cockpit view. Theatre
loading subsequently places the aircraft at the region's authored spawn.

Regression coverage exercises the production menu, actual GUI navigation and
activation, long-list scrolling, stable focus on refresh, modal input isolation,
both pause reasons, and 640×360, 360×640 and 1280×720 layouts. A production scene
fixture validates F-22 startup, cockpit position and menu pause wiring without
downloading terrain. The settings fixture was also rendered and visually checked
with the Compatibility renderer at desktop and small landscape sizes.

The complete headless suite passed: 70/70 tests.
