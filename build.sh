#!/usr/bin/env bash
rip liblovetrack.dylib
clang -shared -F/System/Library/PrivateFrameworks -framework MultitouchSupport -framework CoreFoundation -lpthread -o liblovetrack.dylib lovetrack_lib.m
cp liblovetrack.dylib demos/love2d/
