#!/bin/sh
cat > /tmp/ct.ps <<'EOF'
%!PS-Adobe-3.0
<</PageSize [612 792]>> setpagedevice
0 0 0 setrgbcolor /Helvetica-Bold findfont 16 scalefont setfont
40 752 moveto (COLOR TARGET  --  native vs CUPS) show
/Helvetica findfont 8 scalefont setfont
40 738 moveto (Print natively AND via the bridge; compare saturation/vividness of each labeled patch. Flat = washed out.) show
/PW 80 def /PH 44 def
/patch {
  /yy exch def /xx exch def /nm exch def /bb exch def /gg exch def /rr exch def
  rr gg bb setrgbcolor xx yy PW PH rectfill
  0 0 0 setrgbcolor 0.4 setlinewidth xx yy PW PH rectstroke
  /Helvetica findfont 7 scalefont setfont xx yy 9 sub moveto nm show
} def
1 0 0 (R 255 0 0) 40 686 patch
0 1 0 (G 0 255 0) 132 686 patch
0 0 1 (B 0 0 255) 224 686 patch
0 1 1 (C 0 255 255) 316 686 patch
1 0 1 (M 255 0 255) 408 686 patch
1 1 0 (Y 255 255 0) 500 686 patch
1 0.5 0 (orange) 40 616 patch
0 0.63 0.63 (teal) 132 616 patch
0.5 0 0.78 (purple) 224 616 patch
0.86 0.08 0.24 (crimson) 316 616 patch
0 0.6 1 (sky) 408 616 patch
0.16 0.7 0.16 (grass) 500 616 patch
0.94 0.78 0.67 (skin 1) 40 546 patch
0.78 0.59 0.47 (skin 2) 132 546 patch
0.59 0.39 0.31 (skin 3) 224 546 patch
0.55 0.27 0.07 (brown) 316 546 patch
0.5 0.5 0 (olive) 408 546 patch
0 0 0.5 (navy) 500 546 patch
showpage
EOF
ps2pdf -sPAPERSIZE=letter /tmp/ct.ps /mnt/c/Claude/clawmon-arm64/bridge/COLORTARGET.pdf 2>&1 | tail -1
echo "COLORTARGET.pdf rebuilt as Letter: $(wc -c < /mnt/c/Claude/clawmon-arm64/bridge/COLORTARGET.pdf) bytes"
