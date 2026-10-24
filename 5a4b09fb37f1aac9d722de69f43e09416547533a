"""Developer helper. Python 3 + pyshp; not needed to run Netzblick.

Usage: python build_geodata.py dbip-country-lite-YYYY-MM.csv.gz countries.zip YYYY-MM output
Sources: DB-IP Country Lite (CC BY 4.0); Natural Earth 1:110m admin 0 (public domain).
Both input files are supplied explicitly; this helper does not download anything.
"""
import csv
import gzip
import hashlib
import ipaddress
import json
from pathlib import Path
import struct
import sys
import tempfile
import zipfile

import shapefile


def build(csv_gz, world_zip, version, output):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    tables = {4: [], 6: []}
    with gzip.open(csv_gz, "rt", encoding="utf-8") as source:
        for start, end, code in csv.reader(source):
            a, b = ipaddress.ip_address(start), ipaddress.ip_address(end)
            assert a.version == b.version and int(a) <= int(b)
            assert len(code) == 2 and code.isascii()
            tables[a.version].append((int(a), int(b), code))
    with (output / "geo-country.bin").open("wb") as out:
        out.write(b"NBG1" + struct.pack("<ii", len(tables[4]), len(tables[6])))
        for family, width in [(4, 4), (6, 16)]:
            previous = -1
            for start, end, code in sorted(tables[family]):
                assert start > previous, "Overlapping database ranges"
                previous = end
                out.write(start.to_bytes(width, "big") + end.to_bytes(width, "big") + code.encode("ascii"))
    geometry = []
    countries = {}
    with tempfile.TemporaryDirectory() as temp:
        with zipfile.ZipFile(world_zip) as archive:
            # Read only the fixed Natural Earth files, never extract arbitrary paths.
            for suffix in ("shp", "shx", "dbf"):
                name = "ne_110m_admin_0_countries." + suffix
                (Path(temp) / name).write_bytes(archive.read(name))
        reader = shapefile.Reader(str(Path(temp) / "ne_110m_admin_0_countries.shp"))
        for record in reader.iterShapeRecords():
            props = record.record.as_dict()
            code = props["ISO_A2_EH"]
            if isinstance(code, str) and len(code) == 2 and code != "-99":
                countries[code] = (float(props["LABEL_Y"]), float(props["LABEL_X"]), props["NAME_EN"])
            points = record.shape.points
            parts = list(record.shape.parts) + [len(points)]
            for start, end in zip(parts, parts[1:]):
                ring = points[start:end]
                if len(ring) < 3:
                    continue
                coords = [(round((lon + 180) / 360 * 1000, 2), round((90 - lat) / 180 * 500, 2)) for lon, lat in ring]
                geometry.append("M " + " L ".join(f"{x:.2f},{y:.2f}" for x, y in coords) + " Z")
    (output / "world.path").write_text("\n".join(geometry), encoding="ascii")
    (output / "countries.tsv").write_text("\n".join(f"{code}\t{lat}\t{lon}\t{name}" for code, (lat, lon, name) in sorted(countries.items())) + "\n", encoding="utf-8")
    (output / "geo-version.txt").write_text(f"DB-IP Country Lite {version}\n", encoding="utf-8")
    manifest = {
        "release": version,
        "ipv4_ranges": len(tables[4]), "ipv6_ranges": len(tables[6]),
        "country_coordinates": len(countries),
        "accuracy": "country only; map markers are country label coordinates, not server locations",
        "source_csv_sha256": hashlib.sha256(Path(csv_gz).read_bytes()).hexdigest(),
        "source_map_sha256": hashlib.sha256(Path(world_zip).read_bytes()).hexdigest(),
        "sources": ["https://db-ip.com/db/download/ip-to-country-lite", "https://www.naturalearthdata.com/downloads/110m-cultural-vectors/110m-admin-0-countries/"],
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    build(*sys.argv[1:])
