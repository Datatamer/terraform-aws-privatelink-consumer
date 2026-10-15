import sys
import zipfile

source, output = sys.argv[1], sys.argv[2]

info = zipfile.ZipInfo("index.py", date_time=(1980, 1, 1, 0, 0, 0))
info.external_attr = 0o644 << 16
info.compress_type = zipfile.ZIP_STORED

with open(source, "rb") as f, zipfile.ZipFile(output, "w") as zf:
    zf.writestr(info, f.read())
