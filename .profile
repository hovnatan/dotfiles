export QT_QPA_PLATFORMTHEME=gtk2
source ~/.local_profile
export POINTER_DEVICE_ID_TO_SUSPEND=(xinput --list | sed -rn 's/.*Mouse.*Mouse.*id=([0-9]+).*/\1/p')
