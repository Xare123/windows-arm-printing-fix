#!/bin/sh
# Sample what the CUPS renderer (poppler; sRGB passthrough) delivers for each patch of
# COLORTARGET.pdf, and compare to the known input sRGB. Run in WSL.
#   extract-cups-colors.sh [COLORTARGET.pdf]
PDF="${1:-COLORTARGET.pdf}"
[ -f "$PDF" ] || { echo "usage: extract-cups-colors.sh <COLORTARGET.pdf>"; exit 1; }
pdftoppm -r 40 "$PDF" /tmp/ctp 2>/dev/null
PPM=$(ls /tmp/ctp-*.ppm 2>/dev/null | head -1)
[ -z "$PPM" ] && { echo "render failed (need poppler-utils)"; exit 1; }
perl - "$PPM" <<'PL'
my $f=shift; open(F,"<:raw",$f) or die;
my $m=<F>; my $dim=<F>; my $mx=<F>;
my ($W,$H)=split /\s+/, $dim; my $hdr=tell(F); my $dpi=40;
my @p=(
 ["R",255,0,0,40,686],["G",0,255,0,132,686],["B",0,0,255,224,686],
 ["C",0,255,255,316,686],["M",255,0,255,408,686],["Y",255,255,0,500,686],
 ["orange",255,128,0,40,616],["teal",0,161,161,132,616],["purple",128,0,199,224,616],
 ["crimson",219,20,61,316,616],["sky",0,153,255,408,616],["grass",41,179,41,500,616],
 ["skin1",240,199,171,40,546],["skin2",199,150,120,132,546],["skin3",150,99,79,224,546],
 ["brown",140,69,18,316,546],["olive",128,128,0,408,546],["navy",0,0,128,500,546],
);
printf "%-8s %-13s %-13s %s\n","patch","input sRGB","CUPS sRGB","|delta|";
my $tot=0;
for my $e (@p){
  my($nm,$ir,$ig,$ib,$x,$y)=@$e;
  my $cx=int(($x+40)*$dpi/72); my $cy=int((792-($y+22))*$dpi/72);
  $cx=$W-1 if $cx>=$W; $cy=$H-1 if $cy>=$H;
  seek(F,$hdr+($cy*$W+$cx)*3,0); read(F,my $px,3); my($r,$g,$b)=unpack("C3",$px);
  my $d=abs($r-$ir)+abs($g-$ig)+abs($b-$ib); $tot+=$d;
  printf "%-8s %-13s %-13s %d\n",$nm,"$ir,$ig,$ib","$r,$g,$b",$d;
}
printf "\ntotal |delta| across 18 patches: %d  (0 = CUPS sends sRGB perfectly)\n",$tot;
PL
