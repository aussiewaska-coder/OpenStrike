#!/usr/bin/env python3
"""Print actual controller edges from the foreground APK's telemetry.

Ask the player to press Select, Home, Start, Turbo, Home. No positional label is
inferred: a hardware-only Turbo must not shift the labels of later events.
"""
import argparse
import json
import socket
import time

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, default=60)
    args = parser.parse_args()
    deadline = time.monotonic() + args.seconds
    try:
        with socket.create_connection(('127.0.0.1', 8787), timeout=3) as connection:
            connection.settimeout(2)
            buffer = b''
            seen = None
            while time.monotonic() < deadline:
                try:
                    data = connection.recv(65536)
                except socket.timeout:
                    continue
                if not data:
                    break
                buffer += data
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    sample = json.loads(line)
                    if 'reply' in sample:
                        continue
                    if 'controller_button_events' not in sample:
                        print('This APK does not expose raw button events; install the new build.', flush=True)
                        return 1
                    events = sample['controller_button_events']
                    if seen is None:
                        seen = max((e['serial'] for e in events), default=0)
                        print('Listening:', sample.get('controller_name', '?'), flush=True)
                        print('Press Select → Home → Start → Turbo → Home, releasing each button.', flush=True)
                    for event in events:
                        if event['serial'] > seen:
                            print(json.dumps(event), flush=True)
                            seen = event['serial']
    except OSError as error:
        print('Controller capture unavailable:', error, flush=True)
        return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
