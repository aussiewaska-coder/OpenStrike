# Map and terrain data attribution

The included Surfers Paradise terrain heightmap is derived from NASA Shuttle
Radar Topography Mission (SRTM) 1 arc-second elevation data, obtained from the
AWS Open Data `elevation-tiles-prod` dataset. The source tile is
`S29E153.hgt.gz`.

Building positions and coastline geometry are © OpenStreetMap contributors and
are available under the Open Database License (ODbL):
https://www.openstreetmap.org/copyright

Building **heights are partly ours, not OSM's**. Where a way carries a `height`
or `building:levels` tag that value is used as given. Most ways carry neither,
and the fallback those builders once wrote — the same handful of metres for
three quarters of a theatre — was replaced by `tools/infer_building_heights.py`,
which states each missing height from the footprint's own size, the tagged
heights nearby, and a deterministic per-building variation. Each chunk records
which model produced it under `height_model`; some also carry `height_source`
`dem`, meaning a Copernicus GLO-30 relief sample. These are estimates made for
an arcade flight game and are not a survey of the real skyline.

The packaged orthorectified ground imagery is exported from the Queensland
Government `LatestStateProgram_AllUsers` public image service. Service
attribution: Includes material © State of Queensland (Department of Natural
Resources and Mines, Manufacturing and Regional and Rural Development); ©
Planet Labs Netherlands B.V. reproduced under licence from Planet and Geoplex,
all rights reserved, 2026.

https://spatial-img.information.qld.gov.au/arcgis/rest/services/Basemaps/LatestStateProgram_AllUsers/ImageServer

Streamed theatres additionally fetch elevation from the same AWS Open Data
`elevation-tiles-prod` dataset — either Mapzen/Terrarium tiles or Copernicus
GLO-30 (`skadi`) degree cells, per the theatre's `elevation_server` — and
aerial imagery from the Queensland service above. Where Queensland imagery
thins out south of the border, NSW imagery comes from the SIX public image
service:

https://maps.six.nsw.gov.au/arcgis/rest/services/public/NSW_Imagery/MapServer

Service attribution: © Department of Customer Service.

Where the device has a Mapbox token (Settings → Storage), streamed imagery is
served from Mapbox Satellite instead, and falls back to the government
services above when a tile is unavailable:

Imagery © Mapbox © OpenStreetMap contributors.
https://www.mapbox.com/about/maps/

Some building heights without an OpenStreetMap `height` or `building:levels`
tag were measured from the Copernicus GLO-30 surface model instead of the
class default; those records carry `"height_source": "dem"`.

Packaged theatres preprocess all map data into game assets and fetch nothing at
run time. Streamed theatres fetch on demand and cache to `user://map_cache`, so
each area is downloaded once and is then available offline; Settings → Storage
can pre-download an entire theatre.
