#!/bin/bash
mkdir -p bin

if [ ! -f "bin/ffmpeg" ]; then
  echo "Downloading ffmpeg via ffmpeg-static..."
  npm install --prefix temp_ffmpeg ffmpeg-static
  mv temp_ffmpeg/node_modules/ffmpeg-static/ffmpeg bin/ffmpeg
  rm -rf temp_ffmpeg
  echo "Successfully downloaded ffmpeg to ./bin/ffmpeg"
else
  echo "ffmpeg already exists in bin/"
fi
