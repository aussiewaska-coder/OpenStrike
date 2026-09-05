# Black buildings, lights on the water, and 224 MB of texture

Three findings from a device session at dusk, taken from screenshots and the
telemetry socket rather than from reading alone.

## Buildings went black at dusk while the ground stayed lit

`building_facade.gdshader` multiplied its albedo by `os_terrain_tint`. That
tint exists to stand in for lighting on the terrain, which is drawn `unshaded`
-- tinting the photograph is how night is made there. The facade is a normally
lit surface, so it took the darkening twice: once in albedo and again from the
light. At dusk the sun sits near 0.14 energy over 0.11 ambient while the tint
is about 0.23, so a wall landed near 0.06 against the terrain's 0.23, roughly
four times darker. The city read as black slabs with lit windows, because the
window emission is driven by `os_night` and was working correctly.

The tint's colour is still wanted -- buildings should take the blue cast of
night with everything else -- so only its brightness is dropped, by dividing
the tint by its own largest channel. White by day leaves it unchanged.

## City lights floated on the Broadwater and lit the hinterland

Lights were gated on `sea < 0.5`, from mesh height against `sea_level_m`. The
height grid samples on the order of a hundred metres, far too coarse to
resolve a canal from its bank, so the canals came through as land and lit up.
Nothing distinguished a city from a paddock either: `lights_density` applied
to all land equally.

The photograph knows both things. Roofs, roads and carparks are bright and
grey; bush and cane are green; water is dark. A luminance and greenness test
on the untinted imagery gates the lights, which keeps them off the water and
out of the bush in one expression, with no new data plumbed through. Chunks
that have no imagery yet get no lights rather than a uniform scatter.

Open: bare farmland is bright and ungreen, so paddocks can still light. If
that shows on device, the town anchors added for the tactical map are already
in the repo and can supply a radial mask.

## The F-22 was holding a quarter of a gigabyte of texture

Telemetry showed texture memory pinned at 465 MB across two sessions, with
fps down from 97-117 to a median of 37 then 51, only ~600 draw calls, and
`process_ms` spiking to 231. `_apply_memory_budget()` rations terrain to land
near 150 MB on a device without a runtime compressor, and it was doing its
job -- 2048 px, ten chunks. The overshoot was outside its accounting.

The F-22's three textures are 4096x4096 and were imported `compress/mode=0`,
Godot's lossless mode, which is uncompressed in VRAM: 85.3 MB each with
mipmaps, 256 MB for the aircraft. Ten terrain chunks at 2048 with mipmaps are
about 224 MB, and the two together are the 465 MB observed.

They now import `compress/mode=2`. `import_etc2_astc` was already true, so the
export produces ETC2: 10.67 MB each, verified from the imported `.etc2.ctex`
files, for 32 MB instead of 256 MB.

This is a large standing cost removed, not yet a proven cause of the frame
rate drop -- those textures were resident yesterday too, when the same scene
held 97-117 fps. The 231 ms main-thread spikes remain unexplained and are the
next thing to chase, with more headroom to chase them in.
