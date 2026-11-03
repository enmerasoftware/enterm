#!/bin/zsh
# Builds whisper-cli from the official source once. The app runs it as a separate process,
# so the model's memory is gone as soon as a dictation ends.
set -e
version=v1.9.5
root=${0:A:h:h}
target="$root/vendor/whisper"
[[ -x "$target/bin/whisper-cli" ]] && { echo "$target/bin/whisper-cli"; exit 0; }
mkdir -p "$target"
cd "$target"
[[ -d source ]] || { curl -fsSL "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/$version.tar.gz" | tar xz; mv "whisper.cpp-${version#v}" source; }
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cmake -S source -B obj -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON -DGGML_METAL_EMBED_LIBRARY=ON -DWHISPER_SDL2=OFF -DWHISPER_FFMPEG=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 >/dev/null
cmake --build obj --target whisper-cli -j 2
mkdir -p bin
cp obj/bin/whisper-cli bin/whisper-cli
echo "$target/bin/whisper-cli"
