all: Frameworks/*.xcframework Frameworks/.symlinks

# Same libmpv release as media_kit_libs_macos_video 1.1.4 (which tracks
# v0.6.0), but the "video-full" asset. The default variant ships an FFmpeg
# built with an explicit --enable-decoder list that omits truehd, so TrueHD
# audio tracks decode to nothing; the full variant includes it.
MPV_XCFRAMEWORKS_VERSION=v0.7.3
MPV_XCFRAMEWORKS_SHA256SUM=088c5a75e5ee0e39277f04723179b721cac20387a57cc7b9a899fd47b830c0a2

.cache/xcframeworks/libmpv-xcframeworks-full-${MPV_XCFRAMEWORKS_VERSION}-macos-universal.tar.gz:
	mkdir -p .cache/xcframeworks
	rm -f .cache/xcframeworks/*.tmp .cache/xcframeworks/*-full-macos-universal.tar.gz
	curl -fL \
		https://github.com/media-kit/libmpv-darwin-build/releases/download/${MPV_XCFRAMEWORKS_VERSION}/libmpv-xcframeworks_${MPV_XCFRAMEWORKS_VERSION}_macos-universal-video-full.tar.gz \
		-o .cache/xcframeworks/libmpv-full.tar.gz.tmp
	shasum -a 256 -c <<< '${MPV_XCFRAMEWORKS_SHA256SUM}  .cache/xcframeworks/libmpv-full.tar.gz.tmp'
	mv .cache/xcframeworks/libmpv-full.tar.gz.tmp .cache/xcframeworks/libmpv-xcframeworks-full-${MPV_XCFRAMEWORKS_VERSION}-macos-universal.tar.gz
	touch .cache/xcframeworks/libmpv-xcframeworks-full-${MPV_XCFRAMEWORKS_VERSION}-macos-universal.tar.gz

.cache/xcframeworks/libmpv-xcframeworks-full-macos-universal.tar.gz: .cache/xcframeworks/libmpv-xcframeworks-full-${MPV_XCFRAMEWORKS_VERSION}-macos-universal.tar.gz
	rm -f .cache/xcframeworks/libmpv-xcframeworks-full-macos-universal.tar.gz
	ln -s libmpv-xcframeworks-full-${MPV_XCFRAMEWORKS_VERSION}-macos-universal.tar.gz .cache/xcframeworks/libmpv-xcframeworks-full-macos-universal.tar.gz

Frameworks/*.xcframework: .cache/xcframeworks/libmpv-xcframeworks-full-macos-universal.tar.gz
	mkdir -p Frameworks
	rm -rf Frameworks/*.xcframework
	tar -xvf .cache/xcframeworks/libmpv-xcframeworks-full-macos-universal.tar.gz --strip-components 1 -C Frameworks
	touch Frameworks/*.xcframework

Frameworks/.symlinks: Frameworks/*.xcframework
	rm -rf Frameworks/.symlinks
	mkdir -p Frameworks/.symlinks/mpv
	sed -i '' 's/\r$$//g' create_framework_symlinks.sh # remove CRLF line terminator added by Flutter packaging (https://github.com/media-kit/media-kit/issues/338)
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv
