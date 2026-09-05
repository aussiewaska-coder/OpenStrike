# Tactical-map place labels

The Y-button tactical map labels Surfers Paradise, Helensvale, Nerang, Burleigh
Heads and Tweed Heads. Coolangatta Airport has a distinct amber airfield symbol
and the subtitle `OOL / GOLD COAST`. These geographic annotations remain
separate from selectable weapon contacts; waypoint placement still works at
their coordinates.

Labels use the same latitude/longitude conversion as the terrain and appear
only inside the loaded theatre and visible map viewport. Their text stays the
same screen size while zooming or panning. Dark backing, outlines, leader lines
and alternative label positions keep them readable on all map layers.

Surfers, Burleigh and Tweed retain the existing catalogue's town anchors.
Helensvale uses Queensland Place Names locality record 46051; Nerang uses
populated-place record 24047. The airport marker uses the aerodrome reference
point, 28°09′52″S / 153°30′17″E.

Sources:
- [Queensland Place Names](https://spatial-gis.information.qld.gov.au/arcgis/rest/services/Location/QldPlaceNames/MapServer/0)
- [Airservices Gold Coast aerodrome chart](https://www.airservicesaustralia.com/aip/pending/dap/BCGAD01-173_27NOV2025.pdf)

Checks cover the production terrain-to-map data path, all six markers, every map
style, overlapping labels, zoom anchoring, filtering unrelated theatres and
keeping geographic annotations out of weapon selection. Existing tactical-map,
terrain-detail, controller, landmark and theatre-selection checks pass.
