#!/usr/bin/python3
"""Check generated artwork and source refresh without network access."""
import importlib.machinery
import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("mark_assets", str(ROOT / "scripts/build-mark-assets"))
spec = importlib.util.spec_from_loader("mark_assets", loader)
assets = importlib.util.module_from_spec(spec)
loader.exec_module(assets)


class MarkAssetsTests(unittest.TestCase):
  def test_white_artwork_and_transparency_survive(self):
    pixels = bytearray(6 * 6 * 4)
    for y in range(1, 5):
      for x in range(1, 5):
        i = (y * 6 + x) * 4
        pixels[i:i + 4] = bytes((255, 255, 255, 255))
    pixels[(1 * 6 + 1) * 4:(1 * 6 + 1) * 4 + 4] = bytes((0, 0, 0, 0))
    with tempfile.TemporaryDirectory() as directory:
      out = Path(directory) / "icon.png"
      assets.write_icon_png(6, pixels, assets.icon_box(6, 6, pixels), out, target=2)
      width, height, result = assets.read_png(out)
    self.assertEqual((width, height), (2, 2))
    self.assertEqual(tuple(result[:4]), (255, 255, 255, 191))
    self.assertEqual(tuple(result[-4:]), (255, 255, 255, 255))

  def test_vector_geometry_and_brand_colour_survive(self):
    geometry = "M0 0 C10 0 45 12 30 32 Z"
    with tempfile.TemporaryDirectory() as directory:
      source = Path(directory) / "source.svg"
      source.write_text(f'<svg xmlns="http://www.w3.org/2000/svg"><rect fill="#70C70E"/>'
                        f'<g><path fill="#FFFFFF" d="{geometry}"/></g></svg>')
      for tinted, colour in ((False, "#70C70E"), (True, "#ffffff")):
        out = Path(directory) / f"mark-{tinted}.svg"
        assets.write_mark_svg(source, out, tinted=tinted)
        mark = ET.parse(out).getroot()
        self.assertEqual(len(mark), 1)
        self.assertEqual(mark[0].get("d"), geometry)
        self.assertEqual(mark[0].get("fill"), colour)

  def test_existing_cache_is_refreshed(self):
    with tempfile.TemporaryDirectory() as directory:
      cache = Path(directory) / "omarchy-dim" / "logo.png"
      cache.parent.mkdir()
      cache.write_bytes(b"old logo")
      def download(url, path):
        Path(path).write_bytes(b"new logo")
      with patch.dict(assets.os.environ, {"XDG_CACHE_HOME": directory}), \
           patch.object(assets.urllib.request, "urlretrieve", side_effect=download) as fetch:
        result = assets.load_source("", assets.LOGO_URL, "logo.png")
      self.assertEqual(result.read_bytes(), b"new logo")
      fetch.assert_called_once()


if __name__ == "__main__":
  unittest.main()
