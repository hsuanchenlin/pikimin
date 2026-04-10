#!/bin/bash
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
$ANDROID_HOME/emulator/emulator -avd Pixel_7_Play -no-snapshot-load -gpu host -dns-server 8.8.8.8 &
