"""Regenerate the deterministic compact-search fixture (requires reportlab).

Usage: python generate_search_text_hebrew.py /path/to/DejaVuSans.ttf
The font's license is included in search_text_hebrew.LICENSE.
"""

import sys
import unicodedata
from pathlib import Path

from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

pdfmetrics.registerFont(TTFont('SearchTestHebrew', sys.argv[1]))
output = Path(__file__).with_name('search_text_hebrew.pdf')
pdf = canvas.Canvas(str(output), pagesize=(600, 800), invariant=1, pageCompression=1)
pdf.setTitle('pdfrx compact search parity fixture')
pdf.setAuthor('pdfrx test fixture')
texts = ['שָׁלוֹם עוֹלָם', 'בְּרֵאשִׁית בָּרָא אֱלֹהִים', 'English 123 — עברית מְנֻקֶּדֶת']
for rotation in (0, 90):
    pdf.setPageRotation(rotation)
    pdf.setFont('SearchTestHebrew', 16)
    y = 700
    for text in texts:
        x = 550
        for char in text:
            if not unicodedata.combining(char):
                x -= pdfmetrics.stringWidth(char, 'SearchTestHebrew', 16)
            pdf.drawString(x, y, char)
        y -= 40
    pdf.drawString(30, 500, 'left column: alpha   beta')
    pdf.drawString(320, 500, 'right column: Gamma 456')
    pdf.drawString(30, 460, 'Regex (test) and case CASE')
    pdf.showPage()
pdf.save()
