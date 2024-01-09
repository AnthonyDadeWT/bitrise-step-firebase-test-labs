#!/bin/bash
set -ex

#
# --- Export Environment Variables for other Steps:
# You can export Environment Variables for other Steps with
#  envman, which is automatically installed by `bitrise setup`.
# A very simple example:
#envman add --key EXAMPLE_STEP_OUTPUT --value 'the value you want to share'
# Envman can handle piped inputs, which is useful if the text you want to
# share is complex and you don't want to deal with proper bash escaping:
#  cat file_with_complex_input | envman add --KEY EXAMPLE_STEP_OUTPUT
# You can find more usage examples on envman's GitHub page
#  at: https://github.com/bitrise-io/envman

#
# --- Exit codes:
# The exit code of your Step is very important. If you return
#  with a 0 exit code `bitrise` will register your Step as "successful".
# Any non zero exit code will be registered as "failed" by `bitrise`.


#=======================================
# Main
#=======================================


echo "Configs:"
echo "* service_credentials_file_path: $service_account_credentials_file"
echo "* project: $project_id"
echo "* integration_test_path: $integration_test_path"
echo "* locale: $locale"
echo "* orientation: $orientation"
echo "* test_ios: $test_ios"
echo "* test_android: $test_android"
echo "* build_flavor: $build_flavor"
echo "* firebase_additional_flags: $firebase_additional_flags"

# iOS
echo "* simulator_model: $simulator_model"
echo "* deployment_target: $deployment_target"
echo "* ios_configuration: $ios_configuration"
echo "* scheme: $scheme"
echo "* output_path: $output_path"
echo "* product_path: $product_path"
echo "* workspace: $workspace"
echo "* config_file_path: $config_file_path"
echo "* xcode_version: $xcode_version"
echo "* xcodebuild_additional_flags: $xcodebuild_additional_flags"

# Android
echo "* device_model: $device_model"
echo "* android_version: $android_version"
echo "* android_test_type: $android_test_type"


if [[ $service_account_credentials_file == http* ]]; then
          echo "Service Credentials File is stored as a remote url, downloading it ..."
          curl $service_account_credentials_file --output credentials.json
          service_account_credentials_file=$(pwd)/credentials.json
          echo "Downloaded Service Credentials File to path: ${service_account_credentials_file}"
fi

if [ -z "${service_account_credentials_file}" ] ; then
    echo "Service Account Credential File is not defined"
    exit 1
fi

if [ -z "${project_id}" ] ; then
    echo "Firebase Project ID is not defined"
    exit 1
fi

if [ ! -f "${service_account_credentials_file}" ] ; then
    echo "Service Account Credential path is defined but the file does not exist at path: ${service_account_credentials_file}"
    exit 1
fi

if [ -z "${integration_test_path}" ] ; then
    echo "The path to the integration tests you'd like to deploy is not defined"
    exit 1
fi

# Authenticate and set project
gcloud auth activate-service-account --key-file=$service_account_credentials_file
gcloud --quiet config set project $project_id

##### Android Deployment #####
if [ "${test_android}" == "true" ] ; then
    
    pushd android

    if [ -z "${BITRISE_APK_PATH}"] && [ -z "${build_flavor}" ] ; then
        echo "APK not found, building APK"
        flutter build apk 
    elif [ -z "${BITRISE_APK_PATH}" ] && [ ! -z "${build_flavor}" ] ; then 
        echo "APK not found, building APK with flavor $build_flavor"
        flutter build apk --flavor $build_flavor
    else 
        echo "APK is already built, moving on!"
    fi

    ./gradlew app:assembleAndroidTest
    ./gradlew app:assembleDebug -Ptarget=$integration_test_path

    popd

    echo "🚀 Deploying Android Tests to Firebase 🚀"
    
    if [ -z "${BITRISE_APK_PATH}" ] && [ -z "${build_flavor}" ] ; then 
        gcloud firebase test android run --async --type $android_test_type \
        --app build/app/outputs/apk/debug/app-debug.apk \
        --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
        --device model=$simulator_model,version=$android_version,locale=$locale,orientation=$orientation \
        $firebase_additional_flags
    elif [ -z "${build_flavor}" ] ; then
        gcloud firebase test android run --async --type $android_test_type \
        --app $BITRISE_APK_PATH \
        --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
        --device model=$simulator_model,version=$android_version,locale=$locale,orientation=$orientation \
        $firebase_additional_flags
    else
        gcloud firebase test android run --async --type $android_test_type \
        --app build/app/outputs/apk/$build_flavor/debug/app-$build_flavor-debug.apk \
        --test build/app/outputs/apk/androidTest/$build_flavor/debug/app-$build_flavor-debug-androidTest.apk \
        --device model=$simulator_model,version=$android_version,locale=$locale,orientation=$orientation \
        $firebase_additional_flags
    fi
fi

##### iOS Deploy WIP #####
if [ "${test_ios}" == "true" ] ; then
    
    echo "🚀 Deploying iOS Tests to Firebase 🚀"

    if [ -z "${build_flavor}" ] ; then
        flutter build ios $integration_test_path --release

        pushd ios

        xcodebuild build-for-testing \
        -workspace $workspace \
        -scheme $scheme \
        -xcconfig $config_file_path \
        -configuration $ios_configuration \
        -derivedDataPath \
        $output_path -sdk iphoneos \
        $xcodebuild_additional_flags

        popd

        pushd $product_path
        zip -r "ios_tests.zip" "$ios_configuration-iphoneos" "Runner_iphoneos$$deployment_target-arm64.xctestrun"
        popd
    
        # Running this command asynchrounsly avoids wasting runtime on waiting for test results to come back
        gcloud firebase test ios run --async \
            --test $product_path/ios_tests.zip \
            --device model=$simulator_model,version=$xcode_version,locale=$locale,orientation=$orientation
            $firebase_additional_flags

    else
        flutter build ios --flavor $build_flavor $integration_test_path --release

        pushd ios

        xcodebuild build-for-testing \
        -workspace $workspace \
        -scheme $scheme \
        -xcconfig $config_file_path \
        -configuration "$ios_configuration-$build_flavor" \
        -derivedDataPath \
        $output_path -sdk iphoneos
        $xcodebuild_additional_flags

        popd

        pushd $product_path
        echo "checking folder"
        ls

        if [ "${build_flavor}" == "${scheme}" ] ; then
            zip -r "ios_tests.zip" "$ios_configuration-$build_flavor-iphoneos" "${build_flavor}_${build_flavor}_iphoneos$deployment_target-arm64.xctestrun"
        else
            zip -r "ios_tests.zip" "$ios_configuration-$build_flavor-iphoneos" "Runner_iphoneos$deployment_target-arm64.xctestrun"
        fi

        popd

        # Running this command asynchrounsly avoids wasting runtime on waiting for test results to come back
        gcloud firebase test ios run --async \
            --test $product_path/ios_tests.zip \
            --device model=$simulator_model,version=$xcode_version,locale=$locale,orientation=$orientation
            $firebase_additional_flags
    fi
fi
