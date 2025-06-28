#!/usr/bin/env bash
clang -shared -F/System/Library/PrivateFrameworks -framework MultitouchSupport -framework CoreFoundation -lpthread -o liblovetrack.dylib lovetrack_lib.m
