#!/bin/bash

source build.config

STARTTIME=$(date +%s);


RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BWHITE='\033[1;37m'
DGRAY='\033[1;30m'
NC='\033[0m' # No Color


set -e # strong checking
#set -x # debugging -- do this by passing -debug_build

#
# Troubleshooting
#
# If you get errors about EACCESS when running this script, with regards to
# updating dependencies, ensure you are the owner:
#
#    sudo chown -R `whoami` <path_that_is_inaccessible>
#


#
# TODO:
# record hash in the build notes
# and use API to get the last build's notes
# then build new notes based on commit history between the releases
#
function update_version {
 local config_file="$(pwd)/config.xml"
 local config_json="$(pwd)/www/config.json"
 /usr/bin/env ruby <<-EORUBY

  require 'rexml/document'
  require 'json'
  include REXML

  config_file = "${config_file}"
  config_json = "${config_json}"

  f = File.new(config_file)
  doc = Document.new(f)
  widget = XPath.first(doc, '/widget')
  version = widget.attributes['version']#.gsub(/\d+$/,${BUILD_NO}.to_s)
  puts "Version is #{version}\n"
  puts "Build number is ${BUILD_NO}\n"

  widget.attributes['android-versionCode'] = "${BUILD_NO}"
  widget.attributes['ios-CFBundleVersion'] = "${BUILD_NO}"
  #widget.attributes['version'] = version

  doc.write(File.open(config_file,"w"), 2)

  o = JSON.parse(File.read(config_json))
  o['versioncode'] = "${BUILD_NO}"
  File.open(config_json, 'w') do |file|
    file.write o.to_json
  end

EORUBY

}

function get_version {
local config_file="$(pwd)/../../config.xml"
 /usr/bin/env ruby <<-EORUBY

  require 'rexml/document'
  include REXML

  config_file = "${config_file}"

  f = File.new(config_file)
  doc = Document.new(f)
  widget = XPath.first(doc, '/widget')
  version = widget.attributes['version']

  puts version
EORUBY
}

function findVersionLinkFromResponse() { /usr/bin/env ruby <<-EORUBY
	require 'json'
	parsed_response = JSON.parse('$1')
	puts parsed_response['public_url']
EORUBY
}

function markSchemeSharedAndManual {
    if ! gem spec xcodeproj > /dev/null 2>&1; then
      echo -e "${RED}Gem xcodeproj is not installed!${NC}"
      echo ""
      return 1
    fi
    local PROJECT_FILE="$1"
    local TARGET="$2"
    /usr/bin/ruby <<-EORUBY
        require 'xcodeproj'
        xcproj = Xcodeproj::Project.open("${PROJECT_FILE}")

        # mark shared
        xcproj.recreate_user_schemes

        # mark to manually provision
        target_id = xcproj.targets.select {|target| target.name == "${TARGET}" }.first.uuid
        attributes = xcproj.root_object.attributes['TargetAttributes'] ||= {}
        target_attributes = attributes[target_id] ||= {}
        target_attributes['ProvisioningStyle'] = 'Manual'

        xcproj.save
EORUBY
    return 0
}
function adjustApiEndpoint {

  # sed -i .bak "s/apiBaseUrl:.*/apiBaseUrl: 'https:\/\/${API_HOST}',/g" www/app/util/constants.js
  # rm www/app/util/constants.js.bak >/dev/null
  echo . >/dev/null
}

function templatize {
  # the intent of this function is to pull content from the web and inject it into the
  # content bundle of the app. This can be used to pull in privacy statements, etc
  # that may be shared between the web and app

#   local title="$2"
#   local remote_file="https://someplace.com/legal/_${1}"
#   local template_path="www/app/about/_static_template.html"
#   local output_path="www/app/about/$1"
#   local temp_path="www/app/about/$1.tmp"
# 
#   echo -e "Downloading ${remote_file} ==> ${output_path}"
#   curl -s -o ${temp_path} ${remote_file}
#   sed "/{{content}}/{
#     r ${temp_path}
#     d
#   }" ${template_path} > ${output_path}
# 
#   sed -i .bak "s/{{title}}/${title}/g" "${output_path}"
#   rm -f ${temp_path} >/dev/null
#   rm -f ${output_path}.bak >/dev/null
# 
#   #perl -pe "s/{{content}}/`curl -s ${remote_file}`/e" ${template_path} > ${output_path}
echo .>/dev/null
}

function publish {
  HOCKEY_APP_ID=$1
  BINARY_PATH=$2
  VERSION=$(get_version)
  ### Uploading to Hockeyapp
  echo -e "--- Uploading to Hockeyapp [Time Elapsed $(($(date +%s) - $STARTTIME))s]"
  
		# ipa - optional (required, if dsym is not specified for iOS or Mac), file data of the .ipa for iOS, .app.zip for Mac OS X, or .apk file for Android
		# dsym - optional, file data of the .dSYM.zip file (iOS and OS X) or mapping.txt (Android); note that the extension has to be .dsym.zip (case-insensitive) for iOS and OS X and the file name has to be mapping.txt for Android.
		# notes - optional, release notes as Textile or Markdown (after 5k characters notes are truncated)
		# notes_type - optional, type of release notes:
		# 	0 - Textile
		# 	1 - Markdown
		# notify - optional, notify testers (can only be set with full-access tokens):
		# 	0 - Don't notify testers
		# 	1 - Notify all testers that can install this app
		# 	2 - Notify all testers
		# status - optional, download status (can only be set with full-access tokens):
		# 	1: Don't allow users to download or install the version
		# 	2: Available for download or installation
		# strategy - optional, replace or add build with same build number
		# 	add to add the build as a new build to even if it has the same build number (default)
		# 	replace to replace to a build with the same build number
		# tags - optional, restrict download to comma-separated list of tags
		# teams - optional, restrict download to comma-separated list of team IDs; example:
		# 	12,23,42 with 12, 23, and 42 being the database IDs of your teams
		# users - optional, restrict download to comma-separated list of user IDs; example:
		# 	1224,5678 with 1224 and 5678 being the database IDs of your users
		# mandatory - optional, set version as mandatory:
		# 	0 - no
		# 	1 - yes
		# commit_sha - optional, set to the git commit sha for this build
		# build_server_url - optional, set to the URL of the build job on your build server
		# repository_url - optional, set to your source repository

  ADDITIONAL_PARAMS="" # to be used to optionally pass in notes, etc
  if [ -n "${CI_BUILD_URL}" ]; then ADDITIONAL_PARAMS="${ADDITIONAL_PARAMS} -F \"build_sever_url\"=${CI_BUILD_URL}"; fi
  if [ -n "${CIRCLE_BUILD_URL}" ]; then ADDITIONAL_PARAMS="${ADDITIONAL_PARAMS} -F \"build_sever_url\"=${CIRCLE_BUILD_URL}"; fi  
  
  UPLOAD_RESPONSE=$(curl \
    -F "status=2" \
    -F "notify=0" \
    -F "ipa=@${BINARY_PATH}" \
    -H "X-HockeyAppToken: ${HOCKEY_API_TOKEN}" \
    ${ADDITIONAL_PARAMS} https://rink.hockeyapp.net/api/2/apps/${HOCKEY_APP_ID}/app_versions/upload)
  PUBLIC_URL=$(findVersionLinkFromResponse "${UPLOAD_RESPONSE}")
  if [ -z "${HOCKEY_APP_ID}" ] || [ -z "${HOCKEY_API_TOKEN}" ]; then
    echo -e ${RED}"HOCKEY_APP_ID or HOCKEY_API_TOKEN not set. Cannot determine download and config urls${NC}"
  else
    echo -e Download url: ${BWHITE}${PUBLIC_URL}${NC}
    #echo Config url:   $(findVersionLink "config_url" "$VERSION" "$HOCKEY_APP_ID")
  fi  
}

function showHelp() {
    echo ''
    echo ''
    echo './build.sh [[-release|-debug] -publish -ios -android -install -debug_build -? --help -help]'
    echo ''
    echo ' -release     create a release build'
    echo ' -debug       create a non-release build'
    echo ' -publish     push the build to Hockey'
    echo ' -install     install the build to a tethered device'
    echo ' -android     build only android'
    echo ' -ios         build only ios'
    echo ' -debug_build display all script output for debugging this build script'
    echo ' -ci          build is being done on CI server'
    echo ''
    echo 'By default, both android and ios builds are produced in non-release and are not published to Hockey'
    echo ''
    echo ' -? --help -help displays this message'
    echo ''
    echo ''
}

ROOT_DIR="$(pwd)"

PUBLISH="N"
BUILD_IOS="Y"
BUILD_ANDROID="Y"
DEBUG_BUILD="N"
INSTALL="N"
BUILD_TYPE="Release"
IS_CISERVER=$(if [[ -n "${CI}" ]]; then echo "Y"; else echo "N"; fi)
IS_RELEASE="N"
PRIVATE_REPO_FOLDER="${PWD##*/}-private"
XCODE_PROFILE_FOLDER="~/Library/MobileDevice/Provisioning Profiles/"
DEVELOPMENT_TEAM_ID=${DEVELOPMENT_TEAM_ID-$(if [[ ${SIGNING_IDENTITY} =~ \((.*)\)$ ]]; then echo ${BASH_REMATCH[1]}; else echo ""; fi)}
TARGET=${TARGET-${PROJECT_NAME}}

if [ -z "$API_HOST" ]; then
  API_HOST="api.someplace.com"
fi

if [ "$#" -eq 0 ]; then showHelp; exit; fi

for var in "$@"; do
    var=$(echo -e "$var" | tr '[:upper:]' '[:lower:]')
    if [ "$var" == "-publish" ]; then PUBLISH="Y"; fi
    if [ "$var" == "-ios" ]; then BUILD_IOS_EXP="Y"; fi
    if [ "$var" == "-android" ]; then BUILD_ANDROID_EXP="Y"; fi
    if [ "$var" == "-debug_build" ]; then DEBUG_BUILD="Y"; fi
    if [ "$var" == "-debug" ]; then BUILD_TYPE="Debug"; fi
    if [ "$var" == "-install" ]; then INSTALL="Y"; fi
    if [ "$var" == "-release" ]; then IS_RELEASE="Y"; fi
    if [ "$var" == "-ci" ]; then IS_CISERVER="Y"; fi
    if [ "$var" == "-?" ]; then showHelp; exit; fi
    if [ "$var" == "--help" ]; then showHelp; exit; fi
    if [ "$var" == "-help" ]; then showHelp; exit; fi
done

if [ -z "$BUILD_IOS_EXP" ] && [ -n "$BUILD_ANDROID_EXP" ]; then
  BUILD_IOS="N"
fi
if [ -z "$BUILD_ANDROID_EXP" ] && [ -n "$BUILD_IOS_EXP" ]; then
  BUILD_ANDROID="N"
fi

if [ "$DEBUG_BUILD" == "Y" ] || [ "$IS_CISERVER" == "Y" ]; then
  BUILD_OUT="/dev/stdout"
  DEBUG_BUILD="Y"
  set -x
else
	BUILD_OUT=$(mktemp)
fi


BUILD_TYPE_LOWER=$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')

### Set build number
echo -e "--- Setting version info [Time Elapsed $(($(date +%s) - $STARTTIME))s]"
BUILD_NO=$(git rev-list HEAD --count)

VERSION_INFO=$(update_version)
echo -e "${YELLOW}${VERSION_INFO}${NC}"
VERSION_STRING=$(grep -o -E '[0-9]+\.[0-9]+\.[0-9]+' <<< ${VERSION_INFO})
if [ "${PUBLISH}" == "Y" ]; then
  adjustApiEndpoint
fi



echo -e "use ${BWHITE}tail -f ${BUILD_OUT}${NC} to view the output."

### Install dependencies
echo -e "--- Install dependencies [Time Elapsed $(($(date +%s) - $STARTTIME))s]"

#/usr/local/bin/npm install  >> ${BUILD_OUT} 2>&1
#/usr/local/bin/bower install  >> ${BUILD_OUT} 2>&1
npm install  >> ${BUILD_OUT} 2>&1
bower install  >> ${BUILD_OUT} 2>&1

### Restore ionic platforms
echo -e "--- Restore ionic platforms [Time Elapsed $(($(date +%s) - $STARTTIME))s]"

#/usr/local/bin/ionic state restore
if [ "$BUILD_IOS" == "Y" ]; then
  cordova platform remove ios >> ${BUILD_OUT} 2>&1
  cordova platform add ios >> ${BUILD_OUT} 2>&1
  cordova prepare ios >> ${BUILD_OUT} 2>&1
fi

if [ "$BUILD_ANDROID" == "Y" ]; then
  cordova platform remove android >> ${BUILD_OUT} 2>&1
  cordova platform add android >> ${BUILD_OUT} 2>&1
  cordova prepare android >> ${BUILD_OUT} 2>&1
fi



# templatize 'privacy.html' 'Privacy'
# templatize 'terms.html' 'Terms'


### Build
echo -e "--- Build [Time Elapsed $(($(date +%s) - $STARTTIME))s]"

#/usr/local/bin/gulp sass     # perform sass compiling
#/usr/local/bin/gulp build   # does pre-build gulp stuff like minify
gulp sass

#TODO: echo out all the build parameters

if [ "$BUILD_IOS" == "Y" ]; then
  ### Moving to ios build directory
  echo -e "--- Moving to ios build directory [Time Elapsed $(($(date +%s) - $STARTTIME))s]"

  cd platforms/ios

  ### Copying provisioning profile
  mkdir -p dir "${XCODE_PROFILE_FOLDER}"
  echo -e "--- Copying provisioning profile [Time Elapsed $(($(date +%s) - $STARTTIME))s]"

  PROVISIONING_PROFILE="$(/usr/libexec/PlistBuddy -c "Print UUID" /dev/stdin <<< $(security cms -D -i ${PROVISIONING_PROFILE_PATH}))"
  PROVISIONING_PROFILE_NAME="$(/usr/libexec/PlistBuddy -c "Print Name" /dev/stdin <<< $(security cms -D -i ${PROVISIONING_PROFILE_PATH}))"
  cp "${PROVISIONING_PROFILE_PATH}" "${XCODE_PROFILE_FOLDER}${PROVISIONING_PROFILE}.mobileprovision"
  if [ "${IS_RELEASE}" == "Y" ]; then
    RELEASE_PROVISIONING_PROFILE="$(/usr/libexec/PlistBuddy -c "Print UUID" /dev/stdin <<< $(security cms -D -i ${RELEASE_PROVISIONING_PROFILE_PATH}))"
    RELEASE_PROVISIONING_PROFILE_NAME="$(/usr/libexec/PlistBuddy -c "Print Name" /dev/stdin <<< $(security cms -D -i ${RELEASE_PROVISIONING_PROFILE_PATH}))"
    cp "${RELEASE_PROVISIONING_PROFILE_PATH}" "${XCODE_PROFILE_FOLDER}/${RELEASE_PROVISIONING_PROFILE}.mobileprovision"
  fi

  ### Setting location services permission message
#  echo -e "--- Setting location services permission message [Time Elapsed $(($(date +%s) - $STARTTIME))s]"
#  if [ -z $(/usr/libexec/PlistBuddy -c 'print ":NSLocationWhenInUseUsageDescription"' ${PLIST} 2>/dev/null) ]; then
#    /usr/libexec/PlistBuddy -c "Add :NSLocationWhenInUseUsageDescription string ${LOCATION_MESSAGE}" "${PLIST}"
#  fi

  markSchemeSharedAndManual "${PWD}/${PROJECT_NAME}.xcodeproj" "${TARGET}"
  if [[ $? == 1 ]]; then
    cd "$ROOT_DIR"
    exit
  fi

  ### Cleaning Xcode
  echo -e "--- Cleaning Xcode [Time Elapsed $(($(date +%s) - $STARTTIME))s]"

  mkdir -p "${ROOT_DIR}/builds"
  ARCHIVE_PATH="${ROOT_DIR}/builds/${PROJECT_NAME}"

  /usr/bin/xcodebuild clean             \
      -project "${PROJECT_NAME}.xcodeproj"  \
      -configuration ${BUILD_TYPE}      \
      -alltargets                       \
      &> "$BUILD_OUT"

  ### Archiving
  echo -e "--- Archiving [Time Elapsed $(($(date +%s) - $STARTTIME))s]"

  ARCHIVE_PATH="$(pwd)/${PROJECT_NAME}.xcarchive"
  rm -rf "${ARCHIVE_PATH}"

  if [ "$DEBUG_BUILD" == "N" ]; then
    echo -e "Building iOS... use ${BWHITE}tail -f ${BUILD_OUT}${NC} to view the output."
  fi
  rm -rf "${PROJECT_NAME}.xcarchive"
  /usr/bin/xcodebuild archive             \
      -project "${PROJECT_NAME}.xcodeproj"  \
      -scheme "${SCHEME_NAME}"              \
      -archivePath "${ARCHIVE_PATH}"        \
      DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM_ID}" \
      PROVISIONING_PROFILE="${PROVISIONING_PROFILE}" \
      CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}" \
      >> "$BUILD_OUT"  2>&1
  if [[ $? == 0 ]]; then
    echo -e "${GREEN}Success!${NC}"
    echo -e "Archive at ${ARCHIVE_PATH}"
  else
    echo -e ""
    if [ "$DEBUG_BUILD" == "N" ]; then
      tail -n 50 "${BUILD_OUT}"
    fi
    echo -e ""
    echo -e "${RED}Failed!!${NC}"
    echo -e ""
    echo -e "See log (${BUILD_OUT}) for details."
    echo -e ""
    exit
  fi

  echo -e "Building IPA from Archive..."
  EXPORT_PLIST="$(pwd)/${PROJECT_NAME}.ExportOptions.plist"
  /usr/libexec/PlistBuddy -c "Add :uploadSymbols bool false" "${EXPORT_PLIST}" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :uploadBitcode bool false" "${EXPORT_PLIST}" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :compileBitcode bool false" "${EXPORT_PLIST}" >/dev/null

  IPA_MODIFIER='adhoc'

  if [ "${IS_RELEASE}" == "Y" ]; then
    /usr/libexec/PlistBuddy -c "Add :method string app-store" "${EXPORT_PLIST}"
    IPA_MODIFIER='store'
    xcodebuild -exportArchive -exportOptionsPlist "${EXPORT_PLIST}" -archivePath "${ARCHIVE_PATH}" -exportPath "${IPA_PATH}" PROVISIONING_PROFILE_SPECIFIER="${RELEASE_PROVISIONING_PROFILE_NAME}" >> "$BUILD_OUT"  2>&1
     echo -e "AppStore build can be found at ${IPA_PATH}"
  fi

  IPA_FOLDER="${ROOT_DIR}/builds"
  IPA_FILENAME="${PROJECT_NAME}.ipa"
  IPA_PATH="${IPA_FOLDER}/${IPA_FILENAME}"
  /usr/libexec/PlistBuddy -c "Add :method string ad-hoc" "${EXPORT_PLIST}"
  xcodebuild -exportArchive -exportOptionsPlist "${EXPORT_PLIST}" -archivePath "${ARCHIVE_PATH}" -exportPath "${IPA_FOLDER}" PROVISIONING_PROFILE_SPECIFIER="${PROVISIONING_PROFILE_NAME}" >> "$BUILD_OUT"  2>&1
  if [ -f "${IPA_PATH}" ]; then
    IPA_FILENAME=$(echo -n "${IPA_FILENAME//[[:space:]]/}")
    IPA_FILENAME="${IPA_FILENAME/.ipa/.$VERSION_STRING.$BUILD_NO.$IPA_MODIFIER.$BUILD_TYPE_LOWER.ipa}"
    IPA_OLD_PATH="${IPA_PATH}"
    IPA_PATH="${IPA_FOLDER}/${IPA_FILENAME}"
    mv "${IPA_OLD_PATH}" "${IPA_PATH}"
  else
    echo -e "${RED}archive failed!${NC} archive not found at ${IPA_PATH}"
    cd ${ROOT_DIR}
    exit
  fi


  echo -e "Build can be found at ${IPA_PATH}"
  if [ "${INSTALL}" == "Y" ]; then
    #TODO: test if transporter chief installed and skip if it is not, with a warning
    transporter_chief.rb "${IPA_PATH}"
  fi

  if [ "${PUBLISH}" == "Y" ]; then
    echo -e "Uploading ${ARCHIVE_PATH} to hockey"

    publish "${HOCKEY_APP_ID_IOS}" "${IPA_PATH}"
  else
    echo -e "Build not published to HockeyApp. Use -publish flag next time to push it to HockeyApp"
  fi

  #TODO: show ipa info



  cd "$ROOT_DIR"
fi

if [ "$BUILD_ANDROID" == "Y" ]; then
  ### Moving to Android build directory
  echo -e "--- Moving to Android build directory [Time Elapsed $(($(date +%s) - $STARTTIME))s]"
  cd platforms/android

  "${GRADLE_HOME}/bin/gradle" wrapper --gradle-version 3.3

  if [ "${IS_RELEASE}" == "Y" ]; then
    ### copy signing stuff from private repo
    cp ../../../${PRIVATE_REPO_FOLDER}/ionic/android/release-signing.properties .
    cp ../../../${PRIVATE_REPO_FOLDER}/ionic/android/release.keystore .
    APK_FILE="android-release.apk"
  else
    APK_FILE="android-debug.apk"
  fi
  APK_PATH="$(pwd)/build/outputs/apk/${APK_FILE}"

  if [ "$DEBUG_BUILD" == "N" ]; then
    echo -e ""
    echo -e "Building Android... use ${BWHITE}tail -f ${BUILD_OUT}${NC} to view the output."
    echo -e ""
  fi
  ./gradlew assemble${BUILD_TYPE} &> "${BUILD_OUT}"


  if [ "$?" -ne "0" ]; then
    echo -e ""
    if [ "$DEBUG_BUILD" == "N" ]; then
      tail -n 50 "${BUILD_OUT}"
    fi
    echo -e ""
    echo -e "see log at ${BUILD_OUT}"
    echo -e ""
    echo -e "Failed!!"
    echo -e ""

    exit
  else
        echo -e "${GREEN}Success!${NC}"
  fi


  if [ -f "${APK_PATH}" ]; then
    APK_OLD_PATH="${APK_PATH}"
    PROJECT_NAME_NOSPACE="$(echo -n "${PROJECT_NAME//[[:space:]]/}")"
    APK_PATH="${ROOT_DIR}/builds/${PROJECT_NAME_NOSPACE}.${VERSION_STRING}.${BUILD_NO}.${BUILD_TYPE_LOWER}.apk"
    mv "${APK_OLD_PATH}" "${APK_PATH}"
  else
    echo -e "${RED}archive failed!${NC} archive not found at ${APK_PATH}"
    cd ${ROOT_DIR}
    exit
  fi


  if [ -f "${APK_PATH}" ]; then
    echo -e ""
    echo -e "build can be found at ${APK_PATH}"
    if [ "${PUBLISH}" == "Y" ]; then
      publish "${HOCKEY_APP_ID_ANDROID}" "${APK_PATH}"
    else
      echo -e "Build not published to HockeyApp. Use -publish flag next time to push it to HockeyApp"
      echo -e ""
      if [ "${INSTALL}" == "Y" ]; then
        echo -e ""
        echo -e "Installing APK..."
        adb install -r "${APK_PATH}"
        echo -e ""
      fi
    fi
  else
    echo -e ""
    echo -e "${RED}APK not created at ${APK_PATH}${NC}"
    echo -e ""
  fi

  cd "${ROOT_DIR}"
fi

### cleanup
#git checkout www/app/util/constants.js
#git checkout config.xml

### Summary
echo -e "-- Total time $(($(date +%s) - $STARTTIME))s"
