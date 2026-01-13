#!/usr/bin/python3
import re
import os
import argparse


def read_mods_from_file(ini):
    with open(ini) as f:
        for line in f:
            if 'Mods=' in line:
                mod_ids = line.replace('Mods=', '')
                mod_ids = mod_ids.strip()
                mod_ids = mod_ids.split(';')
            elif 'WorkshopItems' in line:
                workshop_ids = line.replace('WorkshopItems=', '')
                workshop_ids = workshop_ids.strip()
                workshop_ids = workshop_ids.split(';')
    
    print('Number of mod IDs: {}'.format(len(mod_ids)))
    print('Number of workshop IDs: {}'.format(len(workshop_ids)))
    for i, v in enumerate(mod_ids):
        try:
            print(f'{v}, {workshop_ids[i]}')
        except IndexError:
            print(v)


def read_mods_from_disk(zomboid_dir):
    mods = []
    workshop_ids = []
    mod_ids = []
    for (root,dirs,files) in os.walk(zomboid_dir, topdown=True):
        for name in files:
            if name == 'mod.info':
                mods.append(os.path.join(root, name))

    for path in mods:
        workshop_ids.append(path.split('/')[8])
        with open(path) as f:
            mod_ids .append(re.findall(r'id=(.+)', f.read())[0])
    
    for i, v in enumerate(mod_ids):
        print(f'{v}, {workshop_ids[i]}')


def generate_strings(modlist):
    mod_ids = []
    workshop_ids = []
    with open(modlist) as f:
        for line in f.readlines():
            line = line.replace('\ufeff', '')
            try:
                mod_id, workshop_id = line.split(',')
            except ValueError:
                print(line)
                raise
            mod_ids.append(mod_id.strip())
            workshop_ids.append(workshop_id.strip())
    
    mod_id_str = ';'.join(mod_ids)
    ini_mod_str = str(f'Mods={mod_id_str.strip()}')
    yaml_mod_str = str(f'"MOD_NAMES={mod_id_str}"')

    workshop_id_str = ';'.join(workshop_ids)
    ini_workshop_str = str(f'WorkshopItems={workshop_id_str}')
    yaml_workshop_str = str(f'"MOD_WORKSHOP_IDS={workshop_id_str}"')
    
    with open('project_zomboid/PigeonGrindhouse.ini') as f:
        ini = f.read()

    with open('project_zomboid/PigeonGrindhouse.ini', 'w') as f:
        ini = re.sub(r'Mods=.+', ini_mod_str, ini)
        ini = re.sub(r'WorkshopItems=.+', ini_workshop_str, ini)
        f.write(ini)

    with open('docker-compose.yaml') as f:
        yaml = f.read()
    
    with open('docker-compose.yaml', 'w') as f:
        yaml = re.sub(r'"MOD_NAMES=.+', yaml_mod_str, yaml)
        yaml = re.sub(r'"MOD_WORKSHOP_IDS=.+', yaml_workshop_str, yaml)
        f.write(yaml)
    

def main(args):
    if args.gen:
        generate_strings('project_zomboid/mod_list.csv')
    
    if args.read == 'file':
        read_mods_from_file('project_zomboid/PigeonGrindhouse.ini')
    elif args.read == 'disk':
        read_mods_from_disk('/opt/zomboid/ZomboidDedicatedServer')
    pass


parser = argparse.ArgumentParser()
parser.add_argument('-read', default='', help='Reads current mods in ini or from disk and prints')
parser.add_argument('-gen', action='store_true', help='Read csv and generate mod strings')

args = parser.parse_args()

main(args)
