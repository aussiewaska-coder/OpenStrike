"""Send one command to OpenStrike's loopback telemetry socket and print the reply.

    python3 tools/telemetry_cmd.py '{"set": {"fog_density": 0.0001}}'
    python3 tools/telemetry_cmd.py '{"screenshot": true}' --out shot.png

Knobs under "set": day_cycle_enabled, time_mode (0 real, 1 noon, 2 dusk,
3 night), fog_enabled, fog_density, fog_aerial_perspective, fog_sky_affect,
fog_light_color [r,g,b], tonemap_mode (0 linear, 2 filmic, 3 aces, 4 agx),
tonemap_exposure, tonemap_white, ambient_energy, camera_far, sun_energy,
sky_top_color [r,g,b], sky_horizon_color [r,g,b], terrain_tint [r,g,b],
fog_multiplier, sun_multiplier, weather (0 clear, 1 overcast, 2 rain, 3 storm),
cloud_coverage, cloud_enabled, cloud_steps (16–128), cloud_shadow_steps (1–5), render_scale_3d (0.5–1.0).
"""
import argparse
import base64
import json
import socket
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", help="JSON object to send")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--out", help="where to write a returned screenshot PNG")
    parser.add_argument("--timeout", type=float, default=20.0, help="seconds to wait for the reply")
    args = parser.parse_args()
    json.loads(args.command)
    try:
        connection = socket.create_connection((args.host, args.port), timeout=args.timeout)
    except OSError as error:
        print(f"could not connect to {args.host}:{args.port}: {error}", file=sys.stderr)
        return 1
    connection.sendall((args.command + "\n").encode("utf-8"))
    buffer = b""
    while True:
        data = connection.recv(65536)
        if not data:
            print("connection closed before a reply", file=sys.stderr)
            return 1
        buffer += data
        while b"\n" in buffer:
            line, buffer = buffer.split(b"\n", 1)
            message = json.loads(line)
            if "reply" not in message:
                continue  # a telemetry sample, not our reply
            png = message.pop("screenshot_png_base64", None)
            if png and args.out:
                with open(args.out, "wb") as handle:
                    handle.write(base64.b64decode(png))
                message["screenshot_written"] = args.out
            print(json.dumps(message))
            return 0


if __name__ == "__main__":
    sys.exit(main())
