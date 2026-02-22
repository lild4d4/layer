import klayout.db as db
import argparse
import numpy as np
from PIL import Image


def insert_slits(pixel_array, max_width_px, slit_width_px, enclosure_px):
    """
    Modifies a binary pixel array (True = metal, False = empty) in-place to
    insert slits complying with DRC rules:
        Slt.c  - Max metal width without requiring a slit: max_width_px pixels
        Slt.a  - Min slit width: slit_width_px pixels
        Slt.f  - Min Metal enclosure of slit: enclosure_px pixels
                 (slits won't be placed within enclosure_px of any metal edge)

    Strategy:
      1. Scan each column (vertical) for runs of metal pixels longer than
         max_width_px and insert horizontal slits to break them up.
      2. Scan each row (horizontal) for runs of metal pixels longer than
         max_width_px and insert vertical slits to break them up.

    The function alternates between H and V passes until stable (max 10
    iterations) because inserting slits in one direction may create new
    violations in the other direction.
    """
    height, width = pixel_array.shape

    def needs_slit_col(col):
        """Return list of row-ranges where a slit should be inserted in a column scan."""
        slits = []
        run_start = None
        for y in range(height):
            if pixel_array[y, col]:
                if run_start is None:
                    run_start = y
            else:
                if run_start is not None:
                    run_len = y - run_start
                    if run_len > max_width_px:
                        slits.append((run_start, y - 1, run_len))
                    run_start = None
        if run_start is not None:
            run_len = height - run_start
            if run_len > max_width_px:
                slits.append((run_start, height - 1, run_len))
        return slits

    def needs_slit_row(row):
        """Return list of col-ranges where a slit should be inserted in a row scan."""
        slits = []
        run_start = None
        for x in range(width):
            if pixel_array[row, x]:
                if run_start is None:
                    run_start = x
            else:
                if run_start is not None:
                    run_len = x - run_start
                    if run_len > max_width_px:
                        slits.append((run_start, x - 1, run_len))
                    run_start = None
        if run_start is not None:
            run_len = width - run_start
            if run_len > max_width_px:
                slits.append((run_start, width - 1, run_len))
        return slits

    def apply_col_slit(col, y_start, y_end):
        """
        Cut a horizontal slit (clears pixels in a column span) centered in the
        run, respecting the enclosure rule on both ends.
        """
        run_len = y_end - y_start + 1
        # We try to place the slit centered; step = max_width_px
        step = max_width_px
        pos = y_start + step  # first slit center
        while pos <= y_end:
            # Slit pixels: [pos - slit_width_px//2 ... pos + slit_width_px - slit_width_px//2 - 1]
            s0 = pos - slit_width_px // 2
            s1 = s0 + slit_width_px - 1
            # Clamp to run but respect enclosure from run edges
            s0 = max(s0, y_start + enclosure_px)
            s1 = min(s1, y_end - enclosure_px)
            if s1 >= s0:
                pixel_array[s0:s1 + 1, col] = False
            pos += step

    def apply_row_slit(row, x_start, x_end):
        """
        Cut a vertical slit (clears pixels in a row span) respecting enclosure.
        """
        step = max_width_px
        pos = x_start + step
        while pos <= x_end:
            s0 = pos - slit_width_px // 2
            s1 = s0 + slit_width_px - 1
            s0 = max(s0, x_start + enclosure_px)
            s1 = min(s1, x_end - enclosure_px)
            if s1 >= s0:
                pixel_array[row, s0:s1 + 1] = False
            pos += step

    # Multi-pass: scan columns then rows until no violations remain
    for iteration in range(10):
        changed = False

        # Vertical scan: look for tall metal columns
        for col in range(width):
            for (y_start, y_end, _) in needs_slit_col(col):
                apply_col_slit(col, y_start, y_end)
                changed = True

        # Horizontal scan: look for wide metal rows
        for row in range(height):
            for (x_start, x_end, _) in needs_slit_row(row):
                apply_row_slit(row, x_start, x_end)
                changed = True

        if not changed:
            break

    return pixel_array


def convert_to_gds(
    input_filepath,
    output_filepath,
    cellname='TOP',
    scale=1.0,
    threshold=128,
    invert=False,
    invert_alpha=False,
    merge=False,
    smooth=False,
    pixel_size=6,
    layer=71,
    datatype=20,
    # DRC slit parameters (Slt rules)
    apply_slit_rules=True,
    max_metal_width=30.0,   # Slt.c  [µm]
    min_slit_width=2.80,    # Slt.a  [µm]
    max_slit_width=20.00,   # Slt.b  [µm]
    slit_enclosure=1.0,     # Slt.f  [µm]
):
    ly = db.Layout()
    ly.dbu = 0.001

    top = ly.create_cell(cellname)
    to_um = db.CplxTrans(ly.dbu)
    from_um = to_um.inverted()

    # Open the image
    img = Image.open(input_filepath)

    layer_idx = ly.layer(db.LayerInfo(layer, datatype))

    if not invert_alpha:
        new_image = Image.new("RGBA", img.size, "WHITE")
    else:
        new_image = Image.new("RGBA", img.size, "BLACK")

    new_image.paste(img, (0, 0), img)

    new_image_grayscale = new_image.convert("L")
    new_image_binary = new_image_grayscale.point(lambda x: 255 if x > threshold else 0)
    new_image_binary = new_image_binary.convert("1")

    if scale != 1.0:
        new_image_binary.thumbnail(
            (int(new_image_binary.width * scale), int(new_image_binary.height * scale)),
            Image.LANCZOS
        )

    # ------------------------------------------------------------------ #
    #  DRC slit insertion (Slt.a, Slt.b, Slt.c, Slt.f)                   #
    # ------------------------------------------------------------------ #
    if apply_slit_rules and pixel_size > 0:
        # Convert DRC dimensions from µm to pixels
        max_width_px  = max(1, int(max_metal_width / pixel_size))
        # Use min_slit_width clamped to max_slit_width
        desired_slit_um = min(max(min_slit_width, min_slit_width), max_slit_width)
        slit_width_px = max(1, int(desired_slit_um / pixel_size))
        enclosure_px  = max(0, int(slit_enclosure / pixel_size))

        print(f"[Slt rules] pixel_size={pixel_size}µm  "
              f"max_metal={max_width_px}px ({max_metal_width}µm)  "
              f"slit_w={slit_width_px}px ({desired_slit_um}µm)  "
              f"enclosure={enclosure_px}px ({slit_enclosure}µm)")

        # Convert PIL binary image → numpy bool array
        pixel_array = np.array(new_image_binary, dtype=bool)  # True = white (metal or background)

        # We operate on the "metal" pixels.  If invert is set the "drawn"
        # pixels are the dark (False) ones; temporarily flip so the slit
        # logic always sees metal as True.
        if invert:
            pixel_array = ~pixel_array

        pixel_array = insert_slits(pixel_array, max_width_px, slit_width_px, enclosure_px)

        if invert:
            pixel_array = ~pixel_array

        # Convert back to PIL image
        new_image_binary = Image.fromarray(pixel_array.astype(np.uint8) * 255).convert("1")

    # ------------------------------------------------------------------ #
    #  Rasterise into GDS shapes                                          #
    # ------------------------------------------------------------------ #
    if merge:
        top_region = db.Region()

    for y in range(new_image_binary.height):
        for x in range(new_image_binary.width):
            pixel = new_image_binary.getpixel((x, y))

            if (pixel and not invert) or (not pixel and invert):
                box = db.DBox(0.0, 0.0, pixel_size, pixel_size).moved(
                    x * pixel_size,
                    (new_image_binary.height - y - 1) * pixel_size
                )

                if merge:
                    pixel_polygon = db.DPolygon(box)
                    top_region.insert(from_um * pixel_polygon)
                else:
                    top.shapes(layer_idx).insert(box)

    if merge:
        top_region.merge()

        if smooth:
            top_region = top_region.smoothed(from_um * pixel_size * 0.99)

        top.shapes(layer_idx).insert(top_region)

    ly.write(output_filepath)
    print(f"[Done] Written to {output_filepath}")


if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        prog='img2gds',
        description='Convert an image to GDS format with DRC slit rules (Slt.a/b/c/f)'
    )

    parser.add_argument('image_path')
    parser.add_argument('gds_path')
    parser.add_argument('--cellname',      default='TOP',   help='top cellname')
    parser.add_argument('--pixel-size',    type=float, default=0.3,  help='pixel size in µm')
    parser.add_argument('--scale',         type=float, default=1.0,  help='downscale the image, e.g. 0.5')
    parser.add_argument('--threshold',     type=int,   default=128,  help='threshold to compare against')
    parser.add_argument('--invert',        action='store_true',      help='invert the pixels')
    parser.add_argument('--invert-alpha',  action='store_true',      help='invert the alpha pixels')
    parser.add_argument('--merge',         action='store_true',      help='merge polygons')
    parser.add_argument('--smooth',        action='store_true',      help='smooth merged polygons')
    parser.add_argument('--layer',         type=int,   default=71,   help='GDS layer')
    parser.add_argument('--datatype',      type=int,   default=20,   help='GDS datatype')

    # DRC slit arguments
    parser.add_argument('--no-slit-rules',    dest='apply_slit_rules', action='store_false',
                        help='disable automatic slit insertion (DRC rules Slt.a/b/c/f)')
    parser.add_argument('--max-metal-width',  type=float, default=30.0,
                        help='Slt.c: max metal width in µm before a slit is required (default 30)')
    parser.add_argument('--min-slit-width',   type=float, default=2.80,
                        help='Slt.a: minimum slit width in µm (default 2.80)')
    parser.add_argument('--max-slit-width',   type=float, default=20.0,
                        help='Slt.b: maximum slit width in µm (default 20.0)')
    parser.add_argument('--slit-enclosure',   type=float, default=1.0,
                        help='Slt.f: min metal enclosure of slit in µm (default 1.0)')

    parser.set_defaults(apply_slit_rules=True)
    args = parser.parse_args()

    convert_to_gds(
        args.image_path,
        args.gds_path,
        cellname=args.cellname,
        scale=args.scale,
        threshold=args.threshold,
        invert=args.invert,
        invert_alpha=args.invert_alpha,
        merge=args.merge,
        smooth=args.smooth,
        pixel_size=args.pixel_size,
        layer=args.layer,
        datatype=args.datatype,
        apply_slit_rules=args.apply_slit_rules,
        max_metal_width=args.max_metal_width,
        min_slit_width=args.min_slit_width,
        max_slit_width=args.max_slit_width,
        slit_enclosure=args.slit_enclosure,
    )