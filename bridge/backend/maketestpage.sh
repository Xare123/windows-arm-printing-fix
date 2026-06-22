#!/bin/sh
# Generate the dedicated test page used for ALL print tests (never use real docs).
cat > /tmp/testpage.ps <<'EOF'
%!PS-Adobe-3.0
%%BoundingBox: 0 0 612 792
%%EndComments
0 0 0 setrgbcolor
1.5 setlinewidth
18 18 576 756 rectstroke
/cross { gsave translate 0.8 setlinewidth
  -12 0 moveto 12 0 lineto stroke
  0 -12 moveto 0 12 lineto stroke grestore } def
33 759 cross  579 759 cross  33 33 cross  579 33 cross
/Helvetica-Bold findfont 22 scalefont setfont
40 730 moveto (PRINT BRIDGE  --  TEST PAGE) show
/Helvetica findfont 10 scalefont setfont
40 714 moveto (Full Quality \(1200\) - WSL AirPrint - dedicated test sheet \(do not use real documents\)) show
40 686 moveto /Helvetica findfont 6 scalefont setfont (6pt   The quick brown fox jumps over the lazy dog  0123456789) show
40 672 moveto /Helvetica findfont 8 scalefont setfont (8pt   The quick brown fox jumps over the lazy dog  0123456789) show
40 656 moveto /Helvetica findfont 10 scalefont setfont (10pt  The quick brown fox jumps over the lazy dog) show
40 638 moveto /Helvetica findfont 12 scalefont setfont (12pt  The quick brown fox jumps over the lazy dog) show
40 616 moveto /Helvetica findfont 18 scalefont setfont (18pt  Sharpness and baseline check) show
40 588 moveto /Helvetica-Bold findfont 24 scalefont setfont (24pt  Record   RN   4 WEST) show
gsave 40 520 translate
  1 0 0 setrgbcolor 0   0 64 40 rectfill
  0 1 0 setrgbcolor 68  0 64 40 rectfill
  0 0 1 setrgbcolor 136 0 64 40 rectfill
  0 1 1 setrgbcolor 204 0 64 40 rectfill
  1 0 1 setrgbcolor 272 0 64 40 rectfill
  1 1 0 setrgbcolor 340 0 64 40 rectfill
  0 0 0 setrgbcolor 408 0 64 40 rectfill
  0.5 0.5 0.5 setrgbcolor 476 0 64 40 rectfill
  0 0 0 setrgbcolor /Helvetica findfont 8 scalefont setfont
  4 -11 moveto (R) show 72 -11 moveto (G) show 140 -11 moveto (B) show 208 -11 moveto (C) show
  276 -11 moveto (M) show 344 -11 moveto (Y) show 412 -11 moveto (K) show 480 -11 moveto (50%) show
grestore
gsave 40 460 translate
  0 1 531 { /i exch def 1 i 532 div sub  i 532 div  0.6 setrgbcolor i 0 1 44 rectfill } for
grestore
0 0 0 setrgbcolor /Helvetica findfont 8 scalefont setfont
40 450 moveto (Continuous-tone color gradient \(color + transfer check\)) show
gsave 40 410 translate
  0 1 531 { /i exch def i 531 div setgray i 0 1 28 rectfill } for
grestore
0 0 0 setrgbcolor 40 400 moveto (Grayscale ramp  0 to 100%) show
0 0 0 setrgbcolor /Helvetica findfont 9 scalefont setfont 40 370 moveto (Fine lines / resolution:) show
gsave 150 360 translate 0.25 setlinewidth
  0 1 50 { /i exch def i 6 mul 0 moveto 0 18 rlineto } for stroke
grestore
/Helvetica findfont 9 scalefont setfont
40 28 moveto (If the outer frame, all four corner marks, and the full gradient print, the page is complete - no truncation.) show
showpage
%%EOF
EOF
ps2pdf /tmp/testpage.ps /mnt/c/Claude/clawmon-arm64/bridge/TESTPAGE.pdf 2>&1 | tail -2
echo "TESTPAGE.pdf: $(wc -c < /mnt/c/Claude/clawmon-arm64/bridge/TESTPAGE.pdf) bytes"
pdftoppm -png -r 90 /mnt/c/Claude/clawmon-arm64/bridge/TESTPAGE.pdf /mnt/c/Claude/clawmon-arm64/bridge/backend/_testpage_preview 2>/dev/null
ls /mnt/c/Claude/clawmon-arm64/bridge/backend/_testpage_preview*.png 2>/dev/null
echo MAKETESTPAGE-DONE
