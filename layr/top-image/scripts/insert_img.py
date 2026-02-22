import pya
import argparse

def insert_logo(input_gds, logo_gds, output_gds, cellname, offset=(0, 0)):

    # Read greyhound
    layout = pya.Layout()
    layout.read(input_gds)
    top = layout.top_cell()

    # Read logo
    layout.read(logo_gds)

    # Insert logo
    logo = layout.cell(cellname)
    top.insert(pya.DCellInstArray(logo.cell_index(), pya.DTrans(pya.DTrans.R0, pya.DPoint(offset[0], offset[1]))))

    # Write layout
    layout.write(output_gds)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Insert a image into the layout.')

    parser.add_argument('input_gds')
    parser.add_argument('logo_gds')
    parser.add_argument('output_gds')
    parser.add_argument('x_offset')
    parser.add_argument('y_offset')
    parser.add_argument('cellname')
    
    args = parser.parse_args()
    
    insert_logo(args.input_gds, args.logo_gds, args.output_gds, args.cellname,offset=(int(args.x_offset), int(args.y_offset)))