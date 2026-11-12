cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "mpv_libs")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "mpv_libs_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/mpv_libs/mpv_libs_plugin_c_api.h"
  "mpv_libs_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

file(GLOB MPV_LIBS_BUNDLED "${CMAKE_CURRENT_SOURCE_DIR}/native/*.dll")
if(NOT MPV_LIBS_BUNDLED)
  message(FATAL_ERROR "mpv_libs native libraries missing")
endif()
set(mpv_libs_bundled_libraries ${MPV_LIBS_BUNDLED} PARENT_SCOPE)
