cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(nix_nrf_debug_fixture)

set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  ${CMAKE_CURRENT_SOURCE_DIR}/src/main.c
  ${CMAKE_CURRENT_SOURCE_DIR}/src/wire.h
  ${CMAKE_CURRENT_SOURCE_DIR}/prj.conf)
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/src/main.c main_source)
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/src/wire.h wire_source)
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/prj.conf config_source)
string(SHA256 fixture_hash "${main_source}${wire_source}${config_source}")
string(SUBSTRING ${fixture_hash} 0 8 fixture_tag)
target_compile_definitions(app PRIVATE FIXTURE_BUILD_TAG=0x${fixture_tag}U)
target_sources(app PRIVATE src/main.c)
