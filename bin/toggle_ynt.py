import configparser
import os
import subprocess

FILE = os.getenv('HOME') + '/.dotfiles/.config/dunst/dunstrc'
config = configparser.ConfigParser()
config.read(FILE)

ENTRY = 'ignore_ynt'
SUMMARY_TO_CHECK = 'Ընտանիք'

if ENTRY in config:
    del config[ENTRY]
    subprocess.run(['dunstify', '-t', '5000', f'Turned off {SUMMARY_TO_CHECK}'])
else:
    config[ENTRY] = {'summary': SUMMARY_TO_CHECK, 'format': ""}
    subprocess.run(['dunstify', '-t', '5000', f'Turned on {SUMMARY_TO_CHECK}'])

with open(FILE, 'w') as configfile:
    config.write(configfile)
