#!/bin/env python

import os

GREEN = '\u001b[38;5;46m'
RESET = '\u001b[0m'

HOSTNAME = os.uname()[1]
HOSTNAME = 'vfxcache01'

match HOSTNAME:

    case 'vfxcache01':
        print("Started backup scenario for {}\t\t[".format(HOSTNAME) + GREEN + "  OK  " + RESET + "]")


    case 'vfxserver01':
        print("Started backup scenario for {}\t\t[".format(HOSTNAME) + GREEN + "  OK  " + RESET + "]")

    case 'vfxstorage01':
        print("Started backup scenario for {}\t\t[".format(HOSTNAME) + GREEN + "  OK  " + RESET + "]")

    case 'vfxstorage02':
        print("Started backup scenario for {}\t\t[".format(HOSTNAME) + GREEN + "  OK  " + RESET + "]")

    case _:
        print("No backup scenario for {}.".format(HOSTNAME))
