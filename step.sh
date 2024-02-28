#!/bin/bash
set -e

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
echo "* project_id: $project_id"
echo "* integration_test_path: $integration_test_path"
echo "* locale: $locale"
echo "* orientation: $orientation"
echo "* timeout: $timeout"
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
echo "* dev_target: $dev_target"
echo "* xcodebuild_additional_flags: $xcodebuild_additional_flags"

# Android
echo "* apk_path: $android_apk_path"
echo "* test_apk_path: $android_test_apk_path"
echo "* device_model: $android_device_model_id"
echo "* android_version: $android_version"

# Validating Importants
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
    echo $service_account_credentials_file
    echo "Service Account Credential path is defined but the file does not exist at path: ${service_account_credentials_file}"
    exit 1
fi

if [ -z "${integration_test_path}" ] ; then
    echo "The path to the integration tests you'd like to deploy is not defined"
    exit 1
fi

echo " 🔑 Authenticating to Firebase 🔑 "

# Authenticate and set project
gcloud auth activate-service-account --key-file=$service_account_credentials_file
gcloud --quiet config set project $project_id

##### Android Deployment #####
if [ "${test_android}" == "true" ] ; then
    
    pushd android

    # If the APK does not already exist, build the apk to generate required files in /android for building
    # When Flutter projects are created, .gitignores are also generated in specific folders with files that are ignored
    # by default. In the android/ directory, ./gradlew is one of these files, so we need to have this to build the android app
    #if [ -z "${BITRISE_APK_PATH}" ] && [ -z "${build_flavor}" ] ; then
    #    echo "🛠️ APK not found, building APK 🛠️ "
    #    flutter build apk 
    #elif [ -z "${BITRISE_APK_PATH}" ] && [ ! -z "${build_flavor}" ] ; then 
    #    echo "🛠️ APK not found, building APK with flavor $build_flavor 🛠️"
    #    flutter build apk --flavor $build_flavor
    #else 
    #    echo "😁 APK is already built, moving on! 😁"
    #fi
    
    #echo "🛠️ Building androidTest APK and Android APK with Ptarget={$integration_test_path} 🛠️"

    #./gradlew app:assembleAndroidTest
    #./gradlew app:assembleDebug -Ptarget=$integration_test_path

    popd

    echo "🚀 Deploying Android Tests to Firebase 🚀"
    
    if [ -z "${BITRISE_APK_PATH}" ] && [ -z "${build_flavor}" ] ; then 

        gcloud firebase test android run --async --type instrumentation \
        --app $android_apk_path \
        --test $android_test_apk_path \
        --device model=$android_device_model_id,version=$android_version,locale=$locale,orientation=$orientation \
        --timeout $timeout \
        $firebase_additional_flags

    elif [ -z "${build_flavor}" ] ; then

        gcloud firebase test android run --async --type instrumentation \
        --app $BITRISE_APK_PATH \
        --test $android_test_apk_path \
        --device model=$android_device_model_id,version=$android_version,locale=$locale,orientation=$orientation \
        --timeout $timeout \
        $firebase_additional_flags
        
    else
        
        # Handle the inclusion of build flavor in apk/testapk paths variables
        apk_substring="/apk/"
        test_apk_substring="androidTest/"
        second_substring="app-"
        insertion=$build_flavor

        android_apk_path="${android_apk_path/$apk_substring/${apk_substring}${insertion}/}"
        android_apk_path="${android_apk_path/$second_substring/${second_substring}${insertion}-}"
        
        android_test_apk_path="${android_test_apk_path/$test_apk_substring/${test_apk_substring}${insertion}/}"
        android_test_apk_path="${android_test_apk_path/$second_substring/${second_substring}${insertion}-}"

        gcloud firebase test android run --async --type instrumentation \
        --app $android_apk_path \
        --test $android_test_apk_path \
        --device model=$android_device_model_id,version=$android_version,locale=$locale,orientation=$orientation \
        --timeout $timeout \
        $firebase_additional_flags

    fi
fi

##### iOS Deploy WIP #####
if [ "${test_ios}" == "true" ] ; then

    if [ -z "${build_flavor}" ] ; then
        #echo " 🛠️ Building iOS 🛠️ "

        #flutter build ios $integration_test_path --release

        pushd ios

        #xcodebuild build-for-testing \
        #-workspace $workspace \
        #-scheme $scheme \
        #-xcconfig $config_file_path \
        #-configuration $ios_configuration \
        #-derivedDataPath \
        #$output_path -sdk iphoneos \
        #$xcodebuild_additional_flags

        popd

        pushd $product_path
        #echo "Generated the following products:"
        #ls

        zip -r "ios_tests.zip" "$ios_configuration-iphoneos" "${scheme}_iphoneos$dev_target-arm64.xctestrun"
        popd
    
        echo " 🚀 Deploying iOS Tests to Firebase 🚀 "

        gcloud firebase test ios run --async \
            --test $product_path/ios_tests.zip \
            --device model=$simulator_model,version=$deployment_target,locale=$locale,orientation=$orientation \
            --timeout $timeout \
            $firebase_additional_flags

    else
        #echo " 🛠️ Building iOS 🛠️ "

        #flutter build ios --flavor $build_flavor $integration_test_path --release

        pushd ios

        #xcodebuild build-for-testing \
        #-workspace $workspace \
        #-scheme $scheme \
        #-xcconfig $config_file_path \
        #-configuration "$ios_configuration-$build_flavor" \
        #-derivedDataPath \
        #$output_path -sdk iphoneos
        #$xcodebuild_additional_flags

        popd

        pushd $product_path
        #echo "Generated the following products:"
        #ls

        if [ "${build_flavor}" == "${scheme}" ] ; then
            zip -r "ios_tests.zip" "$ios_configuration-$build_flavor-iphoneos" "${build_flavor}_${build_flavor}_iphoneos$dev_target-arm64.xctestrun"
        else
            zip -r "ios_tests.zip" "$ios_configuration-$build_flavor-iphoneos" "${scheme}_iphoneos$dev_target-arm64.xctestrun"
        fi

        popd

        echo "🚀 Deploying iOS Tests to Firebase 🚀"

        gcloud firebase test ios run --async \
            --test $product_path/ios_tests.zip \
            --device model=$simulator_model,version=$deployment_target,locale=$locale,orientation=$orientation \
            --timeout $timeout \
            $firebase_additional_flags
    fi
fi
