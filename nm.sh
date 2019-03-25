active_connection_path=$( dbus-send --system --print-reply \
                          --dest=org.freedesktop.NetworkManager \
                          /org/freedesktop/NetworkManager \
                          org.freedesktop.DBus.Properties.Get \
                          string:"org.freedesktop.NetworkManager" \
                          string:"ActiveConnections" \
                          | grep ActiveConnection/ | cut -d'"' -f2 )

dbus-send --system --print-reply \
            --dest=org.freedesktop.NetworkManager \
            /org/freedesktop/NetworkManager/ActiveConnection/18 \
            org.freedesktop.DBus.Properties.Get \
            string:"org.freedesktop.NetworkManager.Connection.Active" \
            string:"Devices"


dbus-send --system --print-reply \
            --dest=org.freedesktop.NetworkManager \
            /org/freedesktop/NetworkManager/Devices/0 \
            org.freedesktop.DBus.Properties.Get \
            string:"org.freedesktop.NetworkManager.Device" \
            string:"Interface"
