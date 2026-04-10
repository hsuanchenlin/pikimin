#!/bin/bash
# Pikmin Bloom Walk Simulator
# Uses adb emu for guaranteed real-time sensor delays

ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
ADB="$ANDROID_HOME/platform-tools/adb"

TOTAL_STEPS=50000
GPS_STEP=0.000014  # ~1.5m per step

# --- Fetch current GPS location ---
get_location() {
    local device=$1
    $ADB -s "$device" shell dumpsys location 2>/dev/null \
        | awk '/Location\[gps /{
            gsub(/.*Location\[gps /, "")
            gsub(/ .*/, "")
            print
            exit
        }'
}

# --- Main ---
echo "Pikmin Bloom Walk Simulator"

DEVICE=$($ADB devices 2>/dev/null | grep "emulator" | head -1 | awk '{print $1}')
if [ -z "$DEVICE" ]; then
    echo "No emulator found."
    exit 1
fi
ADBD="$ADB -s $DEVICE"
echo "Found: $DEVICE"

COORDS=$(get_location "$DEVICE")
if [ -z "$COORDS" ]; then
    echo "No GPS location. Set it in the emulator first."
    exit 1
fi

BASE_LAT=$(echo "$COORDS" | cut -d',' -f1)
BASE_LON=$(echo "$COORDS" | cut -d',' -f2)
echo "Location: $BASE_LAT, $BASE_LON"
echo "Walking $TOTAL_STEPS steps. Ctrl+C to stop."

LAT=$BASE_LAT
LON=$BASE_LON
HALF_STEPS=$(( TOTAL_STEPS / 2 ))
# Random direction: 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW
DIR=$(( RANDOM % 8 ))
STEPS_IN_DIR=0
DIR_LENGTH=$(( 30 + RANDOM % 120 ))  # random leg length: 30-150 steps

trap "echo; echo Stopped.; exit 0" INT TERM

for i in $(seq 1 $TOTAL_STEPS); do
    # Pick a new random direction every DIR_LENGTH steps
    STEPS_IN_DIR=$(( STEPS_IN_DIR + 1 ))
    if [ "$STEPS_IN_DIR" -ge "$DIR_LENGTH" ]; then
        STEPS_IN_DIR=0
        DIR_LENGTH=$(( 30 + RANDOM % 120 ))
        if [ "$i" -le "$HALF_STEPS" ]; then
            # Phase 1: wander randomly
            DIR=$(( RANDOM % 8 ))
        else
            # Phase 2: bias toward home
            REMAINING=$(( TOTAL_STEPS - i + 1 ))
            LAT=$(awk -v lat="$LAT" -v base="$BASE_LAT" -v r="$REMAINING" \
                'BEGIN { diff=(base-lat)/r; printf "%.7f", lat+diff }')
            LON=$(awk -v lon="$LON" -v base="$BASE_LON" -v r="$REMAINING" \
                'BEGIN { diff=(base-lon)/r; printf "%.7f", lon+diff }')
        fi
    fi

    # Move in current direction (with slight random wobble)
    WOBBLE=$(awk -v r="$RANDOM" 'BEGIN { printf "%.7f", (r % 10 - 5) * 0.000001 }')
    case $DIR in
        0) LAT=$(awk -v lat="$LAT" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lat + s }')   # N
           LON=$(awk -v lon="$LON" -v w="$WOBBLE" 'BEGIN { printf "%.7f", lon + w }') ;;
        1) LAT=$(awk -v lat="$LAT" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lat + s*0.7 }')  # NE
           LON=$(awk -v lon="$LON" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lon + s*0.7 }') ;;
        2) LON=$(awk -v lon="$LON" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lon + s }')   # E
           LAT=$(awk -v lat="$LAT" -v w="$WOBBLE" 'BEGIN { printf "%.7f", lat + w }') ;;
        3) LAT=$(awk -v lat="$LAT" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lat - s*0.7 }')  # SE
           LON=$(awk -v lon="$LON" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lon + s*0.7 }') ;;
        4) LAT=$(awk -v lat="$LAT" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lat - s }')   # S
           LON=$(awk -v lon="$LON" -v w="$WOBBLE" 'BEGIN { printf "%.7f", lon + w }') ;;
        5) LAT=$(awk -v lat="$LAT" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lat + s*0.7 }')  # SW
           LON=$(awk -v lon="$LON" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lon - s*0.7 }') ;;
        6) LON=$(awk -v lon="$LON" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lon - s }')   # W
           LAT=$(awk -v lat="$LAT" -v w="$WOBBLE" 'BEGIN { printf "%.7f", lat + w }') ;;
        7) LAT=$(awk -v lat="$LAT" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lat - s*0.7 }')  # NW
           LON=$(awk -v lon="$LON" -v s="$GPS_STEP" 'BEGIN { printf "%.7f", lon - s*0.7 }') ;;
    esac

    # Phase 2: also nudge toward home each step
    if [ "$i" -gt "$HALF_STEPS" ]; then
        REMAINING=$(( TOTAL_STEPS - i + 1 ))
        LAT=$(awk -v lat="$LAT" -v base="$BASE_LAT" -v r="$REMAINING" \
            'BEGIN { printf "%.7f", lat + (base-lat)/(r*3) }')
        LON=$(awk -v lon="$LON" -v base="$BASE_LON" -v r="$REMAINING" \
            'BEGIN { printf "%.7f", lon + (base-lon)/(r*3) }')
    fi

    # GPS + geo fix (each adb call takes ~50ms which gives us real timing)
    $ADBD emu geo fix $LON $LAT >/dev/null 2>&1

    # Step cycle — each adb call takes ~50-80ms, giving natural 50ms+ gaps
    # This means the sensor service sees distinct timestamps per value
    # Total step cycle ~500ms = ~2 steps/sec (natural walking cadence)

    # 1. Swing (Z drops well below gravity)
    $ADBD emu sensor set acceleration 0.3:0.4:5.0 >/dev/null 2>&1
    $ADBD emu sensor set gyroscope 0.2:0.3:0.0 >/dev/null 2>&1
    sleep 0.05

    # 2. Heel strike (big Z spike well above gravity — THE key trigger)
    $ADBD emu sensor set acceleration -1.5:2.0:22.0 >/dev/null 2>&1
    sleep 0.05

    # 3. Peak impact
    $ADBD emu sensor set acceleration -2.0:2.5:25.0 >/dev/null 2>&1
    sleep 0.05

    # 4. Settling back toward gravity
    $ADBD emu sensor set acceleration -0.3:0.5:12.0 >/dev/null 2>&1
    sleep 0.05

    # 5. Midstance (gravity baseline — step detector needs to see this valley)
    $ADBD emu sensor set acceleration 0.0:0.0:9.8 >/dev/null 2>&1
    $ADBD emu sensor set gyroscope 0.0:0.0:0.0 >/dev/null 2>&1
    sleep 0.1

    # 6. Toe off (second smaller spike)
    $ADBD emu sensor set acceleration 0.5:-0.6:15.0 >/dev/null 2>&1
    sleep 0.05

    # 7. Return to rest
    $ADBD emu sensor set acceleration 0.0:0.0:9.8 >/dev/null 2>&1
    sleep 0.1

    # Vibrate every 10 steps
    if [ $(( i % 10 )) -eq 0 ]; then
        $ADBD shell cmd vibrator_manager synced -f -d 80 oneshot 80 255 >/dev/null 2>&1 &
    fi

    # Progress
    if [ $(( i % 50 )) -eq 0 ]; then
        PERCENT=$(awk -v i="$i" -v t="$TOTAL_STEPS" 'BEGIN { printf "%d", (i/t)*100 }')
        PHASE="Out"; [ "$i" -gt "$HALF_STEPS" ] && PHASE="Return"
        echo -ne "$PERCENT% | Step $i/$TOTAL_STEPS | $PHASE | $LAT, $LON\r"
    fi
done

echo ""
echo "Done! $TOTAL_STEPS steps completed."
