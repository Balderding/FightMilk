# source tools/env.sh  - puts the build tools on PATH; everything lives on O:, nothing on C:
export FLUTTER_ROOT=/o/appsnotonc/flutter
export ANDROID_HOME="O:\appsnotonc\android-sdk"
export ANDROID_SDK_ROOT=$ANDROID_HOME
export ANDROID_USER_HOME="O:\appsnotonc\android-user-home"
export PUB_CACHE="O:\appsnotonc\pub-cache"
export GRADLE_USER_HOME="O:\appsnotonc\gradle-home"
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-17.0.4.8-hotspot"
export FLUTTER_SUPPRESS_ANALYTICS=true
export PATH="$FLUTTER_ROOT/bin:/o/appsnotonc/android-sdk/cmdline-tools/latest/bin:/o/appsnotonc/android-sdk/platform-tools:$JAVA_HOME/bin:$PATH"
export LLAMA_DIR="O:/appsnotonc/llama.cpp"
