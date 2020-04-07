import json
import subprocess
import time
from pathlib import Path

players_present = subprocess.run(['playerctl', 'status']).returncode
if players_present == 0:
    subprocess.run(['playerctl', 'pause'])
    time.sleep(0.5)

config_path = Path.home() / ".config/pulse/my_conf.json"

config = {}
if config_path.is_file():
    config = json.load(open(config_path))

result = subprocess.run(['get_pulse_cards.sh'], capture_output=True)

card_to_turn_on = -1
for i, line in enumerate(result.stdout.decode().split('\n')):
    if line == "":
        continue
    index, card, profile = line.split()
    if profile != "off":
        config[card] = profile
        subprocess.run(['pacmd', 'set-card-profile', str(index), 'off'])
    else:
        card_to_turn_on = index, card

subprocess.run(
    [
        'pacmd', 'set-card-profile',
        str(card_to_turn_on[0]),
        config.get(card_to_turn_on[1], 'off')
    ]
)
subprocess.run(['dunstify', '-t', '2000', f'Switched to {card_to_turn_on[1]}.'])

json.dump(config, open(config_path, 'w'), indent=2, sort_keys=True)
subprocess.run(['pkill', '-RTMIN+10', 'i3blocks'])
