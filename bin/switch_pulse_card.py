import subprocess
import json
from pathlib import Path

config_path = Path.home() / ".config/pulse/my_conf.json"

config = {}
if config_path.is_file():
    config = json.load(open(config_path))

result = subprocess.run(['get_pulse_cards.sh'], capture_output=True)

for line in result.stdout.decode().split('\n'):
    if line == "":
        continue
    index, card, profile = line.split()
    if profile != 'off':
        config[card] = profile
        subprocess.run(['pacmd', 'set-card-profile', str(index), 'off'])
    else:
        subprocess.run(
            ['pacmd', 'set-card-profile',
             str(index),
             config.get(card, 'off')]
        )
        subprocess.run(['dunstify', '-t', '2000', f'Switched to {card}.'])

json.dump(config, open(config_path, 'w'), indent=2, sort_keys=True)
subprocess.run(['pkill', '-RTMIN+10', 'i3blocks'])
