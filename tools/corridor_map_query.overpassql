# Buildings for the streamed Gold Coast / Tweed corridor.
#
# The building-source box is 36 km across inside the 50 km flight ring. A
# single query for the whole source box returns a
# truncated result: the API answers, but with roughly 17,000 of the 24,755
# building ways it reports under `out count`. Fetch it as four quadrants and
# merge, which stays inside the server's limits.
#
# Full box: -28.24169,153.18175,-27.91831,153.54825  (centre -28.08,153.365)
# Quadrants split at the centre latitude and longitude.

[out:json][timeout:240];
way["building"](-28.24169,153.18175,-28.08,153.365);
out tags geom;
