# On-phone AI: llama.cpp (pinned release b12138) + our small C bridge (wk_llm.cpp).
# llama.cpp source lives outside the repo: set LLAMA_DIR (environment) to a checkout of release b12138,
# or leave it empty and CMake downloads that exact release itself.
cmake_minimum_required(VERSION 3.22)
project(wk_llm C CXX)

set(LLAMA_DIR "" CACHE PATH "llama.cpp source (release b12138); empty = fetch it")

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)          # the app downloads models itself; no network code in the engine
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
if(ANDROID)
  set(GGML_NATIVE OFF CACHE BOOL "" FORCE)       # build for the ABI, not this PC
  if(ANDROID_ABI STREQUAL "arm64-v8a")
    # dot-product + fp16: nearly every 64-bit phone since ~2018. The app checks /proc/cpuinfo for
    # them before loading, so an older chip gets a message instead of a crash.
    set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
  endif()
  if(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)  # its fp16 kernels don't build for 32-bit ARM
  endif()
endif()

# Keep build-machine folder names out of the binaries (compilers embed source paths for messages).
function(wk_neutral_paths dir name)
  add_compile_options("-ffile-prefix-map=${dir}=${name}" "-fmacro-prefix-map=${dir}=${name}")
endfunction()
wk_neutral_paths("${CMAKE_CURRENT_SOURCE_DIR}" "wk")

if(LLAMA_DIR AND EXISTS "${LLAMA_DIR}/CMakeLists.txt")
  wk_neutral_paths("${LLAMA_DIR}" "llama.cpp")
  add_subdirectory(${LLAMA_DIR} llama-build EXCLUDE_FROM_ALL)
else()
  include(FetchContent)
  FetchContent_Declare(llama GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git GIT_TAG b12138 GIT_SHALLOW TRUE)
  FetchContent_GetProperties(llama)
  if(NOT llama_POPULATED)
    FetchContent_Populate(llama)
  endif()
  wk_neutral_paths("${llama_SOURCE_DIR}" "llama.cpp")
  add_subdirectory(${llama_SOURCE_DIR} llama-build EXCLUDE_FROM_ALL)
endif()

add_library(wk_llm SHARED wk_llm.cpp)
target_link_libraries(wk_llm PRIVATE llama)
target_compile_features(wk_llm PRIVATE cxx_std_17)
if(ANDROID)
  target_link_options(wk_llm PRIVATE "-Wl,-z,max-page-size=16384")  # 16 KB page phones
endif()
