#!/bin/sh
# Make the attract movies for AVPlayer on iOS 6 (H.264 main 3.1 + AAC) from the arcade data
# (read only). The Bink videos in data/movie are silent 640x480; the arcade plays
# sound/bgm/attract/*_japan.wav over them (seqAtructMovie), and over playdemo and tutorial
# it also blinks a label (atract_layout_movie_playdemo/tutorial.anm: atract_p_movie_*.png
# at (29, 18), opacity |1 - 2 frac(t)| over a 60-frame cycle), burned in here.
# Needs an ffmpeg with the Bink decoder.
set -e
cd "$(dirname "$0")"
# all threads but 2, left for the system (JOBS= overrides)
JOBS="${JOBS:-$(( $(getconf _NPROCESSORS_ONLN) - 2 ))}"; [ "$JOBS" -ge 1 ] || JOBS=1
SRC="${MOVIE_DATA:-../Wangan Midnight Maximum Tune 3DX+ (Japan)/data}"
WAV="${MOVIE_WAV:-japan}"  # the sound/bgm/attract files' language (tools/convert_en.sh: english)
ENC="-threads $JOBS -c:v libx264 -profile:v main -level 3.1 -pix_fmt yuv420p -preset slow -crf 20 -c:a aac -b:a 128k -ar 44100 -movflags +faststart"

# atruct.bik + opening theme -> intro.mp4 (59.5 s)
[ -f data/intro.mp4 ] || ffmpeg -y -v error -i "$SRC/movie/atruct.bik" -i "$SRC/sound/bgm/attract/opening_$WAV.wav" \
  -map 0:v -map 1:a -shortest $ENC data/intro.mp4

# movie with its sound and the blinking label
label() { # bik wav png out
  ffmpeg -y -v error -i "$SRC/movie/$1" -i "$SRC/sound/bgm/attract/$2" -loop 1 -framerate 30 -i "$SRC/sprite/$3" \
    -filter_complex "[2:v]format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*abs(1-2*mod(T,1))'[l];[0:v][l]overlay=29:18:shortest=1[v]" \
    -map "[v]" -map 1:a -shortest $ENC "data/$4"
}
[ -f data/playdemo.mp4 ] || label playdemo.bik demo_$WAV.wav atract_p_movie_playdemo.png playdemo.mp4
[ -f data/tutorial.mp4 ] || label tutorial.bik tutorial_$WAV.wav atract_p_movie_tutorial.png tutorial.mp4
ls -l data/intro.mp4 data/playdemo.mp4 data/tutorial.mp4
