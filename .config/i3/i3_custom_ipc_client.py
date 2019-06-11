#!/usr/bin/env python3

import socket
import sys

SOCKET_FILE = '/tmp/i3_focus_last'

if __name__ == '__main__':
    client_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client_socket.connect(SOCKET_FILE)
    print(sys.argv[1])
    client_socket.send(sys.argv[1].encode())
    client_socket.close()
