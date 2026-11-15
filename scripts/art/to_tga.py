"""Turns a rendered emblem PNG into a 64 x 64, 32-bit, uncompressed TGA for the game.

Usage: python3 scripts/art/to_tga.py <in.png> <out.tga>
"""
import sys

try:
	from PIL import Image
except ImportError:
	sys.exit("to_tga.py needs Pillow: python3 -m pip install Pillow")


def main():
	if len(sys.argv) != 3:
		sys.exit("usage: to_tga.py <in.png> <out.tga>")
	image = Image.open(sys.argv[1]).convert("RGBA")
	image = image.resize((64, 64), Image.LANCZOS)
	image.save(sys.argv[2])


if __name__ == "__main__":
	main()
