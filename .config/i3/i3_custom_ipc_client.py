#!/usr/bin/env python3

import socket
import sys
import os

DEBUG = "DEBUG_I3_IPC" in os.environ

SOCKET_FILE = '/tmp/i3_focus_last'

if __name__ == '__main__':
    client_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client_socket.connect(SOCKET_FILE)
    if DEBUG:
        print(sys.argv[1])
    client_socket.send(sys.argv[1].encode())
    data = client_socket.recv(1024)
    if DEBUG:
        print(data.decode())
    client_socket.close()
