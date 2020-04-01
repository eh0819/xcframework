#!/bin/bash

# Build the fat binary for a framework
#
# input
#    [ -r true|false ] Whether to show a finder window with the resulting framework
#    default is false

BASE_NAME=`basename $0`


usage()
{
    echo "Build an xcframework for a framework"
    echo "Usage: ${BASE_NAME} [-p iOS|watchOS ] [ -r true|false ]"
    echo "Set -p to the platform that you want to build"
    echo "Set -r true if you want a finder window dispayed containing the resulting file"
    exit 1
}


# add number of arguments check

if [ "$#" -eq 0 ]; then
    usage
elif [ "$#" -eq 3 ] && [ $1 == "-p" ]; then
    if [ $2 == "iOS" ] || [ $2 == "watchOS" ]; then
        # good. we have a valid platform
        echo "Platform $2"
    else
        usage
    fi
else
    # add more cases to handle optional show in finder
    usage
fi


REVEAL_ARCHIVE_IN_FINDER=false

PLATFORM="iOS"


while getopts p:r opt; do
   case $opt in
      p) PLATFORM="${OPTARG}"
         ;;
      r) REVEAL_ARCHIVE_IN_FINDER="${OPTARG}"
         ;;
     \?) echo "Invalid Option: -${OPTARG}" 1>&2
         usage
         ;;
   esac
done

XWORKSPACE=`ls -d *.xcworkspace`
PROJECT_NAME="${XWORKSPACE%.*}"
PROJECT_DIR="${PROJECT_NAME}"
CONFIGURATION="Release"

echo " "
echo "===== Building XCFramework for iOS====="

DERIVED_DATA_DIR_SIMULATOR="Builds/${PLATFORM}/DerivedData-xcframework-iOS"
rm -rf "${DERIVED_DATA_DIR_SIMULATOR}"

ARCHS=""
SDK=""
SCHEME_SUFFIX=""

if [ $PLATFORM == "iOS" ] ; then
    ARCHS="i386 x86_64"
    SDK="iphonesimulator"
    SCHEME_SUFFIX="Production"

elif [ $PLATFORM == "watchOS" ]; then
    ARCHS="i386 armv7k"
    SDK="watchsimulator"
    SCHEME_SUFFIX="WatchOS"
fi

/Users/eh0819/Documents/GitHub/xcframework/.build/release/xcframework build \
    --project "${PROJECT_DIR}.xcworkspace" \
    --name "${PROJECT_NAME}" \
    --ios "${PROJECT_NAME}${SCHEME_SUFFIX}" \
    --output "${DERIVED_DATA_DIR_SIMULATOR}" \
    --build "${DERIVED_DATA_DIR_SIMULATOR}/archive" \
    --verbose \
    -- -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA_DIR_SIMULATOR}" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED="NO" \
    CODE_SIGNING_ALLOWED="NO" \
    BITCODE_GENERATION_MODE=bitcode \
    
    
#xcodebuild \
#    clean \
#    build \
#    CODE_SIGN_IDENTITY="" \
#    CODE_SIGNING_REQUIRED="NO" \
#    CODE_SIGNING_ALLOWED="NO" \
#    BITCODE_GENERATION_MODE=bitcode \
#    ONLY_ACTIVE_ARCH=NO \
#    -UseModernBuildSystem=0 \
#    -workspace "${PROJECT_DIR}.xcworkspace" \
#    -scheme "${PROJECT_NAME}${SCHEME_SUFFIX}" \
#    -sdk "${SDK}" \
#    -configuration "${CONFIGURATION}" \
#    -derivedDataPath "${DERIVED_DATA_DIR_SIMULATOR}" \
#        | /usr/local/bin/xcpretty \
#        | tee ${SDK}.log 2>&1

#The members of the $PIPESTATUS array hold the exit status of each respective command executed in a pipe. $PIPESTATUS[0] holds the exit status of the first command in the pipe, $PIPESTATUS[1] the exit status of the second command, and so on. i.e. ${PIPESTATUS[0] in the above command holds the exit status of xcodebuild command.
#-ne means not equal.
#It is important to assign ${PIPESTATUS[0] to a local variable first. ${PIPESTATUS[0] value changes as soon as you execute another command e.g. any command you use to access ${PIPESTATUS[]}, will automatically replace the current state of the array with the return code of the command you have just run.
XCODE_EXIT_CODE=${PIPESTATUS[0]}
if [ $XCODE_EXIT_CODE -ne 0 ]; then
    echo "ios xcframework failed with exit code: ${XCODE_EXIT_CODE}";
    exit 2
fi

#This checks if the framework is actually generated
#SIMULATOR_FPATH=`find "${DERIVED_DATA_DIR_SIMULATOR}" -name "${PROJECT_NAME}".xcframework" | grep "${PROJECT_NAME}".xcframework"`
#if [ -z "${SIMULATOR_FPATH}" ]
#then
#   echo "!!!!! ERROR: Build for simulator did not create framework !!!!!"
#   exit 8
#fi


# Create directory for universal
echo " "
echo "===== Making universal directory ====="
OUTPUT_DIR=Output
rm -rf "${OUTPUT_DIR}"
mkdir "${OUTPUT_DIR}"

# Create platform subfolder
OUTPUT_DIR="$OUTPUT_DIR/${PLATFORM}"
mkdir "${OUTPUT_DIR}"

# load the framework with the device version
cp -r "${DERIVED_DATA_DIR_SIMULATOR}/${PROJECT_NAME}.xcframework" "${OUTPUT_DIR}/${PROJECT_NAME}.xcframework"

#copy phase

function strip {
local STRING=${1#$"$2"}
echo ${STRING%$"$2"}
}

BRANCHNAME=${3}
BRANCHNAME=$(strip "$BRANCHNAME" "release/v")
DESTINATION="../Output/${BRANCHNAME}/${PLATFORM}"

if [ -d "${DESTINATION}" ]; then

echo "copying the archived framework to path: ${DESTINATION}"
cp -r "${OUTPUT_DIR}/${PROJECT_NAME}.xcframework" "${DESTINATION}"
if [ $? -ne 0 ]; then
  echo "Failed to copy .xcframework to ${DESTINATION}"
  exit 1
fi

echo " "
echo "===== Copy dSYM ====="

DSYMLOCATION="./${DERIVED_DATA_DIR_SIMULATOR}/archive/${PROJECT_NAME}${SCHEME_SUFFIX}-iphoneos.xcarchive/dSYMs/${PROJECT_NAME}.framework.dSYM"
# Copy dSYMs
cp -r "${DSYMLOCATION}" "${DESTINATION}/dSYM/${PROJECT_NAME}.framework.dSYM"
if [ $? -ne 0 ]; then
  echo "Failed to copy .dSYM to ${DESTINATION}/dSYM/"
  exit 1
fi


echo " "
echo "===== Copy bcsymbolmap ====="


BSYMBOLSLOCATIONS="./${DERIVED_DATA_DIR_SIMULATOR}/archive/${PROJECT_NAME}${SCHEME_SUFFIX}-iphoneos.xcarchive/BCSymbolMaps/"

# Copy bcsymbolmap files for the dSYM file
#1. Extract UUIDs from a dSYM file.  There is one build UUID per each CPU architecture built. e.g. armv7 and arm64 in a dSYM for a device build.
UUIDs=$(dwarfdump -u "${DSYMLOCATION}" | sed 's/.*UUID: \(.*\) (.*/\1/')

#2. There is one symbol map per architecture. For each architecture built, find the corresponding bcsymbolmap, symbol map file has ".bcsymbolamp" extension and UUID as the filename
while IFS= read -r UUID; do
    foundSymbolMapFilePath=$(find "$BSYMBOLSLOCATIONS" -name "$UUID.bcsymbolmap")
    if [ -z "$foundSymbolMapFilePath" ]; then #check if foundFilePath is empty
        echo "Error: cannot find bcsymbolfile for UUID: $UUID included in dSYM: ${DEVICE_FPATH}.dSYM in folder: ${BSYMBOLSLOCATIONS}"
        exit 1
    else
        #only create the desitnation symbolmap directory and intermediate directories if they don't exist.
        SYMBOLMAP_DESTINATION="${DESTINATION}/SymbolMap/${PROJECT_NAME}"
        mkdir -p "${DESTINATION}/SymbolMap/${PROJECT_NAME}"
        cp "$foundSymbolMapFilePath" "$SYMBOLMAP_DESTINATION"
    
        #check result $? of the copy command
        if [ $? -ne 0 ]
        then
            echo "Error copying symbolmap file for ${PROJECT_NAME}"
            exit 1
        fi
    fi
done <<< "$UUIDs"

#podspec is platform independent
COMMON_DESTINATION="../Output/${BRANCHNAME}"
# Copy Podspec
cp "${PROJECT_NAME}.podspec" "${COMMON_DESTINATION}/podspecs/"
if [ $? -ne 0 ]; then
  echo "Failed to copy .podspec to ${COMMON_DESTINATION}/podspecs/"
  exit 1
fi

else
 echo "could not find destination folder, skipping copy step"
 exit 1
fi



