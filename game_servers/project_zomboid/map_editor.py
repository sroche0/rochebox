#!/usr/bin/python3
import argparse
import os


def main(args):
    map_files_to_delete = []
    chunk_files_to_delete = []

    if args.coords:
        top_left = [int(x) for x in args.coords[0].split(',')]
        bottom_right = [int(x) for x in args.coords[1].split(',')]
    
    elif args.cells:
        # 1 cell == 30x30 map bins
        chunk_top_left = [int(x) for x in args.cells[0].split('x')]
        top_left = [int(x) * 30 for x in args.cells[0].split('x')]
        chunk_bottom_right = [(int(x)) for x in args.cells[1].split('x')]
        bottom_right = [(int(x) + 1) * 30 for x in args.cells[1].split('x')] # add 30 to the values to get the bottom right corner of the cell

    if top_left[0] > bottom_right[0] or top_left[1] > bottom_right [1]:
        print('coords/cells must be passed top left first and bottom right second')
        exit(1)
    
    print('\nGenerating map file names ...')
    x_values = [top_left[0]]
    chunk_x_values = [chunk_top_left[0]]
    y_values = [top_left[1]]
    chunk_y_values = [chunk_top_left[1]]

    while x_values[-1] != bottom_right[0]:
        x_values.append(x_values[-1] + 1)

    while chunk_x_values[-1] != chunk_bottom_right[0]:
        chunk_x_values.append(chunk_x_values[-1] + 1)

    while y_values[-1] != bottom_right[1]:
        y_values.append(y_values[-1] + 1)

    while chunk_y_values[-1] != chunk_bottom_right[1]:
        chunk_y_values.append(chunk_y_values[-1] + 1)


    map_cells = [(x,y) for x in x_values for y in y_values]
    for cell in map_cells:
        file_name = 'map_{}_{}.bin'.format(cell[0], cell[1])
        if os.path.exists(os.path.join(args.path, file_name)):
            map_files_to_delete.append(file_name)

    chunk_cells = [(x, y) for x in chunk_x_values for y in chunk_y_values]
    for cell in chunk_cells:
        file_name = 'chunkdata_{}_{}.bin'.format(cell[0], cell[1])
        if os.path.exists(os.path.join(args.path, file_name)):
            chunk_files_to_delete.append(file_name)
    
    if not map_files_to_delete and not chunk_files_to_delete:
        print('No files in that range exist. Nothing to do. Exiting...\n')
        exit(0)

    check = 'null'
    while check != 'y':
        try:
            check = input('Delete {} map files {} chunk files? y/n: '.format(
                len(map_files_to_delete), 
                len(chunk_files_to_delete)
            ))
            if check == 'n':
                exit(0)
        except:
            print(map_files_to_delete)
            print(chunk_files_to_delete)
            raise

    counter = 0
    for file_name in map_files_to_delete:
        try:
            file_path = os.path.join(args.path, file_name)
            os.remove(file_path)
            counter += 1
        except FileNotFoundError:
            pass

    for file_name in chunk_files_to_delete:
        try:
            file_path = os.path.join(args.path, file_name)
            os.remove(file_path)
            counter += 1
        except FileNotFoundError:
            pass

    print('Removed {} files\n'.format(counter))


parser = argparse.ArgumentParser()
parser.add_argument('-coords', nargs='+', default=[], help='top left and bottom right x, y coordinates from https://map.projectzomboid.com/')
parser.add_argument('-path', help='path to the server save directory')
parser.add_argument('-cells', nargs='+', default=[], help='top left and bottom right Cell coords in 10x15 format')

if __name__ == '__main__':
    args = parser.parse_args()
    if not any([args.coords, args.cells, len(args.cells) == 2, len(args.coords) == 2]):
        print('ERROR: Need to pass the top left and bottom right coordinates of a square')
        exit(1)
    main(args)
