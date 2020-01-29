import configparser
import os

FILE = os.getenv('HOME') + '/.dotfiles/.config/dunst/dunstrc'
config = configparser.ConfigParser()
config.read(FILE)

ENTRY = 'ignore_ynt'

if ENTRY in config:
    del config[ENTRY]
else:
    config[ENTRY] = {'summary': 'Ընտանիք', 'format': ""}

with open(FILE, 'w') as configfile:
    config.write(configfile)
