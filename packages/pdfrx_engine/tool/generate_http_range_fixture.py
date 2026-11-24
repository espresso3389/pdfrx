"""Generate a deterministic uncompressed PDF; use qpdf --linearize for its pair.

No third-party Python packages are needed. The image streams are deliberately
larger than the native HTTP cache block, exercising contiguous PDFium reads.
"""

import pathlib
import sys

target = pathlib.Path(sys.argv[1])
width = height = 1536
image = bytes((i * 17 + i // 256) % 256 for i in range(width * height * 3))
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
    b"/Resources << /XObject << /Im1 5 0 R >> >> /Contents 4 0 R >>",
]
commands = b"q 612 0 0 792 0 0 cm /Im1 Do Q\n"
objects.append(b"<< /Length %d >>\nstream\n" % len(commands) + commands + b"endstream")
image_header = (
    b"<< /Type /XObject /Subtype /Image /Width %d /Height %d "
    b"/ColorSpace /DeviceRGB /BitsPerComponent 8 /Length %d >>\nstream\n"
    % (width, height, len(image))
)
objects.append(image_header + image + b"\nendstream")
objects.append(
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
    b"/Resources << /XObject << /Im1 8 0 R >> >> /Contents 7 0 R >>"
)
objects.append(b"<< /Length %d >>\nstream\n" % len(commands) + commands + b"endstream")
objects.append(image_header + image[::-1] + b"\nendstream")
output = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = [0]
for index, body in enumerate(objects, 1):
    offsets.append(len(output))
    output += b"%d 0 obj\n" % index + body + b"\nendobj\n"
xref = len(output)
output += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
for offset in offsets[1:]:
    output += b"%010d 00000 n \n" % offset
output += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
target.write_bytes(output)
print(f"{target}: {len(output)} bytes")
