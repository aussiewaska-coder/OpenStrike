# Buildings for the streamed Sydney Harbour theatre.
#
# The building-source box is 36 km across inside the 50 km flight ring
# (centre -33.87,151.20). Sydney is far denser than the Gold Coast corridor,
# so even quadrants time out: fetch it as a 4x4 grid of ~9 km cells and merge.
# Each cell below is one request; concatenate the `elements` arrays, then run:
#
#   python3 tools/build_streamed_buildings.py sydney_merge.json \
#     --latitude -33.87 --longitude 151.20 \
#     --world-size 36000 --chunks 24 \
#     --output-dir data/regions/au_nsw_sydney_harbour/buildings
#
# Full box: -34.0317,151.0053,-33.7083,151.3947  (centre -33.87,151.20)
# Cells split each axis into quarters.
#
# Row 1 (south, airport / Botany):
#   way["building"](-34.0317,151.0053,-33.9509,151.1026); out tags geom;
#   way["building"](-34.0317,151.1026,-33.9509,151.2000); out tags geom;
#   way["building"](-34.0317,151.2000,-33.9509,151.2974); out tags geom;
#   way["building"](-34.0317,151.2974,-33.9509,151.3947); out tags geom;
# Row 2 (south-centre, inner west / CBD south):
#   way["building"](-33.9509,151.0053,-33.8700,151.1026); out tags geom;
#   way["building"](-33.9509,151.1026,-33.8700,151.2000); out tags geom;
#   way["building"](-33.9509,151.2000,-33.8700,151.2974); out tags geom;
#   way["building"](-33.9509,151.2974,-33.8700,151.3947); out tags geom;
# Row 3 (north-centre, harbour / CBD / Parramatta):
#   way["building"](-33.8700,151.0053,-33.7892,151.1026); out tags geom;
#   way["building"](-33.8700,151.1026,-33.7892,151.2000); out tags geom;
#   way["building"](-33.8700,151.2000,-33.7892,151.2974); out tags geom;
#   way["building"](-33.8700,151.2974,-33.7892,151.3947); out tags geom;
# Row 4 (north, Manly / Chatswood / Ryde):
#   way["building"](-33.7892,151.0053,-33.7083,151.1026); out tags geom;
#   way["building"](-33.7892,151.1026,-33.7083,151.2000); out tags geom;
#   way["building"](-33.7892,151.2000,-33.7083,151.2974); out tags geom;
#   way["building"](-33.7892,151.2974,-33.7083,151.3947); out tags geom;

[out:json][timeout:240];
way["building"](-33.8700,151.2000,-33.7892,151.2974);
out tags geom;
