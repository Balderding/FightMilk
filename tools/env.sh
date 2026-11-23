# source tools/env.sh  - puts the build tools on PATH; nothing on C: (but the JDK, see below).
# One variable says where the tools live; move them and change only TOOLS (or set it before
# sourcing). The project folder is found from this file's own place.
# Paths are made with plain bash (no subshells but one): Git Bash can fail to start a subshell
# when the PC is busy, and an empty TEMP sends Gradle and flutter_tools astray.
: "${TOOLS:=X:/tools}"
_here="${BASH_SOURCE[0]%/*}"
PROJECT="$(cd "$_here/.." 2>/dev/null && pwd -W)" # Windows form, e.g. X:/workout-app
[ -n "$PROJECT" ] || PROJECT="X:/workout-app"   # the subshell failed: the project's own folder
# Windows form X:/a/b -> Git Bash form /x/a/b
_unix() { local p="${1//\\//}"; p="${p%/}"; REPLY="/${p:0:1}"; REPLY="${REPLY,,}${p:2}"; }
export FLUTTER_ROOT="$TOOLS/flutter"
export ANDROID_HOME="$TOOLS/android-sdk"
export ANDROID_SDK_ROOT=$ANDROID_HOME
export ANDROID_USER_HOME="$TOOLS/android-user-home"
export PUB_CACHE="$TOOLS/pub-cache"
export GRADLE_USER_HOME="$TOOLS/gradle-home"
# the JDK: the copy in TOOLS (jdk17) when it is there (Windows' own JAVA_HOME is overruled, so
# the build uses X: only), else the one installed on the PC (Temurin 17). To keep a JAVA_HOME of
# your own, set FM_JAVA_SET=1 with it before sourcing.
_unix "$TOOLS/jdk17"
if [ -z "${FM_JAVA_SET:-}" ]; then
  if [ -x "$REPLY/bin/java.exe" ] || [ -x "$REPLY/bin/java" ]; then JAVA_HOME="$TOOLS/jdk17"; fi
fi
: "${JAVA_HOME:=C:/Program Files/Eclipse Adoptium/jdk-17.0.4.8-hotspot}"
export JAVA_HOME
export FLUTTER_SUPPRESS_ANALYTICS=true
_unix "$FLUTTER_ROOT"; _fr="$REPLY"
_unix "$ANDROID_HOME"; _ah="$REPLY"
_unix "$JAVA_HOME"; _jh="$REPLY"
export PATH="$_fr/bin:$_ah/cmdline-tools/latest/bin:$_ah/platform-tools:$_jh/bin:$PATH"
export LLAMA_DIR="$TOOLS/llama.cpp"
# flutter_tools and Gradle use TEMP/TMP; Windows form, or they fall back to C: (review 4 rule)
_t="$PROJECT/work/tmp"
export TEMP="${_t//\//\\}"
export TMP="$TEMP"
unset _here _fr _ah _jh _t
