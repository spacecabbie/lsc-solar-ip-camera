#!/bin/sh
# ptz2.sh - standard ONVIF PTZ hooks for the LSC solar PTZ (3218152) (ms32008 via ms32008v2 start/stop/count).
# ONVIF units (generic spaces, conf max_step_x=max_step_y=1):
#   Position  x 0..1 = pan 0(left stop)..8000 q,  y 0..1 = tilt 0(bottom stop)..2300 q
#   Translation x/y -1..1 = fraction of full travel (x>0 right, y>0 up)
#   Velocity |v| 0..1 -> 300..1500 pps; ContinuousMove runs to the soft limit until Stop.
# pan: dir0=RIGHT(+) dir1=LEFT(-); tilt: dir0=DOWN dir1=UP. Chip counter: pan +q on dir0; tilt +q on dir0.
D=${PTZ_DIR:-/tmp/mnt/sdcard/custom}
B="$D/bin/ms32008v2 --go"
POS=$D/ptz_pos; PRE=$D/ptz_presets; ST=/tmp/ptz2.state; LOCK=/tmp/ptz2.lock; LOG=$D/../logs/ptz2.log
PMAX=8000; TMAX=2300; M=50
log() { read u x < /proc/uptime; echo "$u $*" >> $LOG; }
rdpos() { [ -f $POS ] && read P T C < $POS; P=${P:-4000}; T=${T:-1150}; C=${C:-0}; }
wrpos() { echo "$P $T $C" > $POS.tmp && mv $POS.tmp $POS; }
milli() { v=$1; sg=1; case "$v" in -*) sg=-1; v=${v#-};; esac; i=${v%%.*}; f=${v#*.}; [ "$f" = "$v" ] && f=
  f=${f}000; f=${f%"${f#???}"}; echo $(( sg*(${i:-0}*1000 + 1$f - 1000) )); }
fx() { i=$(($1/1000)); f=$(($1%1000+1000)); echo "$i.${f#1}"; }   # milli -> d.ddd
pps() { v=${1:-1}; v=${v#-}; i=${v%%.*}; f=${v#*.}; [ "$f" = "$v" ] && f=0
  case "$f" in [0-9]*) d=${f%"${f#?}"};; *) d=0;; esac
  [ "${i:-0}" -ge 1 ] 2>/dev/null && d=10; [ $d -lt 1 ] && d=1; echo $((300 + 120*d)); }  # 0.1->420 .. 1.0->1500
cnt() { $B count | while read x a b; do a=${a#tilt=}; b=${b#pan=}; echo $a $b; done; }
s16() { [ $1 -ge 32768 ] && echo $(($1-65536)) || echo $1; }
lock() { mkdir $LOCK 2>/dev/null && return 0; pidof ms32008v2 >/dev/null || { rm -rf $LOCK; mkdir $LOCK; }; }
unlock() { rmdir $LOCK 2>/dev/null; }
# settle: read the chip counter, stop, fold into position. Safe to call any time.
settle() {
  [ -f $ST ] || { $B stop >/dev/null; return; }
  read AX DIR Q T0 < $ST
  set -- $(cnt); a=$(s16 $1); b=$(s16 $2)
  $B stop >/dev/null
  rdpos
  if [ $AX = pan ]; then n=$b; P=$((P+n)); [ $P -lt 0 ] && P=0; [ $P -gt $PMAX ] && P=$PMAX
  else n=$a; T=$((T-n)); [ $T -lt 0 ] && T=0; [ $T -gt $TMAX ] && T=$TMAX; fi
  wrpos; rm -f $ST; log "settle $AX moved=$n -> $P $T"; }
# start AXIS SIGN PPS [TARGET]: one chip move to the soft limit (or target), no wait
start() {
  settle; rdpos
  if [ $1 = pan ]; then cur=$P; lo=$M; hi=$((PMAX-M)); else cur=$T; lo=$M; hi=$((TMAX-M))
    [ $C = 1 ] || { lo=750; hi=1550; }; fi
  if [ $2 -gt 0 ]; then q=$((${4:-$hi}-cur)); else q=$((cur-${4:-$lo})); fi
  q=$((q/4*4))   # full-step mode: chip counts only whole steps (4 q-steps)
  [ $q -le 0 ] && { log "$1 at limit $cur"; return 1; }
  if [ $1 = pan ]; then dir=$(( $2>0 ? 0 : 1 )); else dir=$(( $2>0 ? 1 : 0 )); fi
  $B start $1 $dir $q $3 >/dev/null || { $B stop >/dev/null; return 1; }
  read u x < /proc/uptime; echo "$1 $dir $q $u" > $ST; log "start $1 dir=$dir q=$q pps=$3 from $cur"; }
waitdone() { # poll until the counter reaches q (or timeout s); returns 2 if the move was taken over/stopped
  [ -f $ST ] || return 2; read AX DIR Q T0 < $ST; my=$T0; to=$(( ${1:-60} * 5 )); while [ $to -gt 0 ]; do
    set -- $(cnt); [ $AX = pan ] && n=$2 || n=$1; n=$(s16 $n); n=${n#-}
    [ $n -ge $((Q-3)) ] && return 0; [ -f $ST ] && read a b c t < $ST && [ "$t" = "$my" ] || return 2; usleep 200000; to=$((to-1)); done; return 1; }
home() { # gentle bump into the LEFT / BOTTOM stop at HOME_PPS, then zero
  hp=$HOME_PPS; settle
  if [ $1 = pan ]; then $B start pan 1 8000 $hp >/dev/null; s=$((8000/hp+3))
  else $B start tilt 0 2300 $hp >/dev/null; s=$((2300/hp+3)); fi
  echo "$1 x 99999 0" > $ST; i=0; while [ $i -lt $s ]; do sleep 1; i=$((i+1)); done
  $B stop >/dev/null; rm -f $ST; rdpos; [ $1 = pan ] && P=0 || { T=0; C=1; }; wrpos; log "home $1 -> $P $T"; }
goto() { # AXIS TARGET PPS (blocking)
  rdpos; [ $1 = pan ] && cur=$P || cur=$T; [ $2 = $cur ] && return 0
  [ $2 -gt $cur ] && sg=1 || sg=-1   # tilt: T grows upward, so +1 = up
  start $1 $sg $3 $2 || return 0; waitdone 60; r=$?; [ $r = 2 ] && return 2; settle; }

gotoxy() { # PAN_Q TILT_Q PPS (blocking, sequential axes; the chip's start burst would stop the other channel)
  goto pan $1 $3; [ $? = 2 ] && return; goto tilt $2 $3; }
clampP() { v=$1; [ $v -lt $M ] && v=$M; [ $v -gt $((PMAX-M)) ] && v=$((PMAX-M)); echo $((v/4*4)); }
clampT() { rdpos; lo=$M; hi=$((TMAX-M)); [ $C = 1 ] || { lo=750; hi=1550; }; v=$1; [ $v -lt $lo ] && v=$lo; [ $v -gt $hi ] && v=$hi; echo $v; }
bg() { sh "$0" "$@" </dev/null >/dev/null 2>&1 & }
SP=${TAP_PPS:-1500}; HOME_PPS=${HOME_PPS:-400}; HOME_PAN=${HOME_PAN:-4000}; HOME_TILT=${HOME_TILT:-1148}
case "$1" in
  # ---- ONVIF hooks ----
  left|right|up|down)   # ContinuousMove: start now (synchronous, so a following Stop always finds it)
     lock; case $1 in left) start pan -1 $(pps $2);; right) start pan 1 $(pps $2);; up) start tilt 1 $(pps $2);; down) start tilt -1 $(pps $2);; esac
     unlock; log "cont $1 $2";;
  stop) lock; settle; unlock;;
  rel) log "rel $2 $3"; bg _rel "$2" "$3";;
  abs) log "abs $2 $3"; bg _abs "$2" "$3";;
  getpos) rdpos; echo "$(fx $((P*1000/PMAX))),$(fx $((T*1000/TMAX))),0.0";;
  moving) [ -f $ST ] && echo 1 || echo 0;;
  presets) echo "8=Calibrate,0.5,0.5"; [ -f $PRE ] && while read l; do echo "$l"; done < $PRE;;
  setpreset) rdpos; n=$2; [ "$n" = 8 ] && exit 0
       if [ "$n" -lt 1 ] 2>/dev/null; then n=; for k in 1 2 3 4 5 6 7; do grep -q "^$k=" $PRE 2>/dev/null || { n=$k; break; }; done
         [ -z "$n" ] && { log "setpreset: full"; exit 0; }; fi; { [ -f $PRE ] && while read l; do [ "${l%%=*}" = "$n" ] || echo "$l"; done < $PRE
       echo "$n=$3,$(fx $((P*1000/PMAX))),$(fx $((T*1000/TMAX)))"; } > $PRE.tmp; mv $PRE.tmp $PRE; log "setpreset $n $3 $P $T";;
  rmpreset) [ -f $PRE ] && { while read l; do [ "${l%%=*}" = "$2" ] || echo "$l"; done < $PRE > $PRE.tmp; mv $PRE.tmp $PRE; };;
  preset) if [ "$2" = 8 ]; then bg home; else l=$( [ -f $PRE ] && while read l; do [ "${l%%=*}" = "$2" ] && echo "$l"; done < $PRE )
       [ -n "$l" ] && { set -- $(echo "${l#*=}" | { IFS=, read nm x y; echo $x $y; }); log "preset -> $1 $2"; bg _abs $1 $2; }; fi;;
  sethome) rdpos; echo "$P $T" > $D/ptz_home; log "sethome $P $T";;
  gohome) h="${HOME_PAN:-4000} ${HOME_TILT:-1148}"; [ -f $D/ptz_home ] && read h1 h2 < $D/ptz_home && h="$h1 $h2"
       set -- $h; bg _goq $1 $2;;
  # ---- workers ----
  _rel) mx=$(milli $2); my=$(milli $3); rdpos
       tp=$P; tt=$T; [ $mx = 0 ] || tp=$(clampP $((P + mx*PMAX/1000))); [ $my = 0 ] || tt=$(clampT $((T + my*TMAX/1000))); gotoxy $tp $tt $SP;;
  _abs) mx=$(milli $2); my=$(milli $3); tp=$(clampP $((mx*PMAX/1000))); tt=$(clampT $((my*TMAX/1000))); gotoxy $tp $tt $SP;;
  _goq) gotoxy $(clampP $2) $(clampT $3) $SP;;
  # ---- manual / maintenance ----
  home) lock; home pan; home tilt; unlock; sh "$0" _goq ${HOME_PAN:-4000} ${HOME_TILT:-1148};;
  pos) rdpos; echo "pos $P $T $C";;
  count) $B count;;
esac
exit 0
