#!/usr/bin/env python

import os

def main():

    prj_name = input("Please, enter the project name: ")
    prj_path = '/mnt/vfxserver01/Projects/'

    os.makedirs(prj_path + prj_name, exist_ok=True)
    os.makedirs(prj_path + prj_name + '/3d/_render')
    os.makedirs(prj_path + prj_name + '/materials/prm')
    os.makedirs(prj_path + prj_name + '/materials/src')
    os.makedirs(prj_path + prj_name + '/compose')
    os.makedirs(prj_path + prj_name + '/render')

    print("!!! ------ Done ------ !!!")

if __name__ == '__main__':
    main()

