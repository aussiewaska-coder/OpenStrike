# Q1 was see-through

Q1 rendered as a transparent sliver: most of the tower was missing and you
could see the sky through it.

The three hero-tower GLBs carry no NORMAL attribute, so Godot derives both the
lighting and the back-face culling from triangle winding. The kit's winding is
inconsistent. As Godot imported them, 1177 of Q1's 3548 wall faces were wound
inward, along with 22 of Soul's 140 and 52 of Ocean's 252. Every inward face is
culled, so a third of Q1's shell simply was not drawn. Soul and Ocean lost less
and still read as solid slabs from a distance, which is why only Q1 looked
broken; Soul's roof was open and Ocean's parapet had holes.

Forcing the material double-sided was tried and rejected: the tower goes solid
but renders unlit black, because the generated normals still point inward.
Winding is the single cause of both symptoms, so winding is what was fixed.

`tools/fix_tower_winding.py` rewrites only the index buffer, judging walls
against the tower's vertical axis and roofs and soffits against its centre.
Godot's glTF importer mirrors one axis to convert +Z-forward to -Z-forward,
which reverses winding, so a face has to be wound inward in the file to arrive
outward in the engine. Positions, UVs, textures and the JSON chunk are
untouched. It turned 1393 of Q1's triangles, 44 of Soul's and 98 of Ocean's.

`corridor_landmarks_test.gd` now reads each landmark's imported mesh and fails
when more than a twentieth of its wall faces are wound inward. It fails on the
old assets and passes on the repaired ones. The full suite passes, 81/81, and
all three towers were rendered with the Compatibility renderer and inspected:
Q1 is a complete tower with its facade and spire, Soul is closed at the crown,
Ocean's parapet is whole.

Soul remains a 188-triangle slab with no crown geometry, against Q1's 3985.
That is a modelling gap, not a rendering defect, and is left for a device look
now that its shading is correct.
