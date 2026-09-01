#!/usr/bin/env python3
"""Read OpenStrike's loopback telemetry.

The game listens on 127.0.0.1:8787 and writes one JSON sample per half second to
anything that connects. logcat is unreachable from inside the proot userland the
project is built in, and adb needs a network the phone does not always have;
loopback needs neither.

    python3 tools/read_telemetry.py            # stream samples
    python3 tools/read_telemetry.py --count 20 # take twenty and stop
"""
import argparse
import json
import socket
import sys

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--count", type=int, default=0, help="0 streams forever")
    parser.add_argument("--raw", action="store_true", help="print the JSON as sent")
    args = parser.parse_args()

    try:
        connection = socket.create_connection((args.host, args.port), timeout=10)
    except OSError as error:
        print(f"could not connect to {args.host}:{args.port}: {error}", file=sys.stderr)
        return 1

    buffer = b""
    seen = 0
    with connection:
        connection.settimeout(30)
        while args.count == 0 or seen < args.count:
            try:
                chunk = connection.recv(4096)
            except socket.timeout:
                print("no samples for 30s", file=sys.stderr)
                return 1
            if not chunk:
                break
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                if not line.strip():
                    continue
                seen += 1
                sample = json.loads(line)
                if args.raw:
                    print(json.dumps(sample))
                    continue
                print(
                    "fps %5.1f  proc %6.2fms  phys %5.2fms  draws %5d  "
                    "vram %6.1fMB tex %6.1fMB  |  %s %s  chunk %dm  detail %d/%d(+%d)  "
                    "under %s %dpx  tiles c%d n%d f%d"
                    % (
                        sample.get("fps", 0), sample.get("process_ms", 0),
                        sample.get("physics_ms", 0), sample.get("draw_calls", 0),
                        sample.get("video_mem_mb", 0), sample.get("texture_mem_mb", 0),
                        sample.get("theatre", "?"), sample.get("quality", "?"),
                        sample.get("chunk_m", 0), sample.get("detailed", 0),
                        sample.get("chunks", 0), sample.get("pending", 0),
                        "DETAIL" if sample.get("under_detailed") else "overview",
                        sample.get("under_px", 0), sample.get("cache_hits", 0),
                        sample.get("net_fetches", 0), sample.get("tile_failures", 0),
                    )
                )
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
