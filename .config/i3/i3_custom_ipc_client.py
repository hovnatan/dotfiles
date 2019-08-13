#!/usr/bin/env python3

import socket
import sys
import os

SOCKET_FILE = '/tmp/i3_focus_last'

if __name__ == '__main__':
    client_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client_socket.connect(SOCKET_FILE)
    client_socket.send(sys.argv[1].encode())
    data = client_socket.recv(1024)
    print(data.decode())
    client_socket.close()
