#!/bin/bash
clang -shared -F/System/Library/PrivateFrameworks -framework MultitouchSupport -framework CoreFoundation -o libtrackpad.dylib trackpad_lib.m
