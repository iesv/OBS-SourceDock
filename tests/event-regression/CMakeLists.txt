cmake_minimum_required(VERSION 3.24)
project(source_dock_event_regression LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
find_package(Qt6 REQUIRED COMPONENTS Core Widgets Gui)
find_package(libobs REQUIRED)
find_package(obs-frontend-api REQUIRED)
if(NOT SOURCE_DOCK_DIR)
  message(FATAL_ERROR "Set SOURCE_DOCK_DIR to a Source Dock working copy")
endif()

# Compile the real plugin implementation. Access control is relaxed only for
# this Linux test executable so the production header needs no test hooks.
add_executable(event-regression
  event-regression.cpp
  ${SOURCE_DOCK_DIR}/source-dock.cpp
  ${SOURCE_DOCK_DIR}/source-dock-settings.cpp
  ${SOURCE_DOCK_DIR}/qt-display.cpp
  ${SOURCE_DOCK_DIR}/media-control.cpp
  ${SOURCE_DOCK_DIR}/media-slider.cpp
  ${SOURCE_DOCK_DIR}/volume-meter.cpp
  ${SOURCE_DOCK_DIR}/slider-absoluteset-style.cpp
  ${SOURCE_DOCK_DIR}/source-dock.hpp
  ${SOURCE_DOCK_DIR}/source-dock-settings.hpp
  ${SOURCE_DOCK_DIR}/qt-display.hpp
  ${SOURCE_DOCK_DIR}/media-control.hpp
  ${SOURCE_DOCK_DIR}/media-slider.hpp
  ${SOURCE_DOCK_DIR}/volume-meter.hpp
  ${SOURCE_DOCK_DIR}/slider-absoluteset-style.hpp)
target_include_directories(event-regression PRIVATE ${SOURCE_DOCK_DIR})
target_link_libraries(event-regression PRIVATE
  Qt6::Core Qt6::Widgets Qt6::GuiPrivate OBS::libobs OBS::obs-frontend-api)
target_compile_options(event-regression PRIVATE
  -fno-access-control -fsanitize=address,undefined -fno-omit-frame-pointer)
target_link_options(event-regression PRIVATE -fsanitize=address,undefined)
option(LEGACY_HANDLER "Compile against the unpatched QMouseEvent handler" OFF)
if(LEGACY_HANDLER)
  target_compile_definitions(event-regression PRIVATE LEGACY_HANDLER)
endif()

enable_testing()
add_test(NAME event-regression COMMAND event-regression)
set_tests_properties(event-regression PROPERTIES ENVIRONMENT
  "QT_QPA_PLATFORM=offscreen;ASAN_OPTIONS=detect_leaks=0;UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1")
