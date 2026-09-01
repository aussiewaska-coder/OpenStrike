# Map and terrain data attribution

The included Surfers Paradise terrain heightmap is derived from NASA Shuttle
Radar Topography Mission (SRTM) 1 arc-second elevation data, obtained from the
AWS Open Data `elevation-tiles-prod` dataset. The source tile is
`S29E153.hgt.gz`.

Building positions and coastline geometry are © OpenStreetMap contributors and
are available under the Open Database License (ODbL):
https://www.openstreetmap.org/copyright

The packaged orthorectified ground imagery is exported from the Queensland
Government `LatestStateProgram_AllUsers` public image service. Service
attribution: Includes material © State of Queensland (Department of Natural
Resources and Mines, Manufacturing and Regional and Rural Development); ©
Planet Labs Netherlands B.V. reproduced under licence from Planet and Geoplex,
all rights reserved, 2026.

https://spatial-img.information.qld.gov.au/arcgis/rest/services/Basemaps/LatestStateProgram_AllUsers/ImageServer

Streamed theatres additionally fetch Mapzen/Terrarium elevation tiles from the
same AWS Open Data `elevation-tiles-prod` dataset, and aerial imagery from the
Queensland service above. Where Queensland imagery thins out south of the
border, NSW imagery comes from the SIX public image service:

https://maps.six.nsw.gov.au/arcgis/rest/services/public/NSW_Imagery/MapServer

Service attribution: © Department of Customer Service.

Packaged theatres preprocess all map data into game assets and fetch nothing at
run time. Streamed theatres fetch on demand and cache to `user://map_cache`, so
each area is downloaded once and is then available offline.
