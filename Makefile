.PHONY: build run run-example clean xcode

build:
	swift build --configuration release

run:
	swift run SwiftJSRuntime

run-example:
	swift run SwiftJSRuntime Examples/example.js

clean:
	swift package clean

xcode:
	swift package generate-xcodeproj

setup:
	mkdir -p Sources/SwiftJSRuntime
	mkdir -p Examples
