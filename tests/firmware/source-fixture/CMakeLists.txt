cmake_minimum_required(VERSION 3.20)
list(APPEND EXTRA_ZEPHYR_MODULES ${CMAKE_CURRENT_SOURCE_DIR}/extra)
# Deliberately omit HINTS: workspace-mode tools must supply package discovery.
find_package(Zephyr REQUIRED)
project(source_fixture)
target_sources(app PRIVATE src/main.c)
