#!/usr/bin/env ruby
# frozen_string_literal: true

require "xcodeproj"
require "fileutils"

PROJECT_PATH = "FinderX.xcodeproj"

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)

def configure_common(target, bundle_id)
  target.build_configurations.each do |config|
    config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "14.0"
    config.build_settings["SWIFT_VERSION"] = "6.0"
    config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_id
    config.build_settings["DEVELOPMENT_TEAM"] = ""
    config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
    config.build_settings["CLANG_ENABLE_MODULES"] = "YES"
    config.build_settings["ENABLE_USER_SCRIPT_SANDBOXING"] = "NO"
  end
end

def add_sources(project, target, group_name, paths)
  group = project.main_group[group_name] || project.main_group.new_group(group_name)
  paths.each do |path|
    file = group.find_file_by_path(path) || group.new_file(path)
    target.add_file_references([file])
  end
end

def add_resources(project, target, group_name, paths)
  group = project.main_group[group_name] || project.main_group.new_group(group_name)
  paths.each do |path|
    file = group.find_file_by_path(path) || group.new_file(path)
    target.resources_build_phase.add_file_reference(file)
  end
end

def link_framework(target, framework_target)
  target.add_dependency(framework_target)
  target.frameworks_build_phase.add_file_reference(framework_target.product_reference)
end

def embed_framework(target, framework_target)
  phase = target.new_copy_files_build_phase("Embed Frameworks")
  phase.symbol_dst_subfolder_spec = :frameworks
  build_file = phase.add_file_reference(framework_target.product_reference)
  build_file.settings = { "ATTRIBUTES" => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
end

core = project.new_target(:framework, "ImageCompressionCore", :osx, "14.0")
configure_common(core, "dev.finderx.ImageCompressionCore")
add_sources(project, core, "Sources", ["Sources/ImageCompressionCore/ImageCompressionCore.swift"])
core.build_configurations.each do |config|
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["MARKETING_VERSION"] = "0.1.0"
  config.build_settings["CURRENT_PROJECT_VERSION"] = "1"
end

linking = project.new_target(:framework, "FinderXLinking", :osx, "14.0")
configure_common(linking, "dev.finderx.FinderXLinking")
add_sources(project, linking, "Sources", ["Sources/FinderXLinking/FinderXLink.swift"])
linking.build_configurations.each do |config|
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["MARKETING_VERSION"] = "0.1.0"
  config.build_settings["CURRENT_PROJECT_VERSION"] = "1"
end

xmind_preview_core = project.new_target(:framework, "XMindPreviewCore", :osx, "14.0")
configure_common(xmind_preview_core, "dev.finderx.XMindPreviewCore")
add_sources(project, xmind_preview_core, "Sources", ["Sources/XMindPreviewCore/XMindPreviewCore.swift"])
xmind_preview_core.build_configurations.each do |config|
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["MARKETING_VERSION"] = "0.1.0"
  config.build_settings["CURRENT_PROJECT_VERSION"] = "1"
end

app = project.new_target(:application, "FinderX", :osx, "14.0")
configure_common(app, "dev.finderx.FinderX")
add_sources(project, app, "Sources", ["Sources/FinderXApp/FinderXApp.swift"])
add_resources(project, app, "FinderX", ["FinderX/Resources/Assets.xcassets"])
link_framework(app, core)
link_framework(app, linking)
link_framework(app, xmind_preview_core)
embed_framework(app, core)
embed_framework(app, linking)
embed_framework(app, xmind_preview_core)
app.build_configurations.each do |config|
  config.build_settings["INFOPLIST_FILE"] = "FinderX/Resources/Info.plist"
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "FinderX/Resources/FinderX.entitlements"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../Frameworks"
end

extension = project.new_target(:app_extension, "FinderXFinderExtension", :osx, "14.0")
configure_common(extension, "dev.finderx.FinderX.FinderExtension")
add_sources(project, extension, "Sources", ["Sources/FinderXFinderExtension/FinderSync.swift"])
link_framework(extension, linking)
extension.build_configurations.each do |config|
  config.build_settings["INFOPLIST_FILE"] = "FinderXFinderExtension/Resources/Info.plist"
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "FinderXFinderExtension/Resources/FinderXFinderExtension.entitlements"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks"
  config.build_settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
end

embed_extensions = app.new_copy_files_build_phase("Embed App Extensions")
embed_extensions.symbol_dst_subfolder_spec = :plug_ins
extension_file = embed_extensions.add_file_reference(extension.product_reference)
extension_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
app.add_dependency(extension)

thumbnail_extension = project.new_target(:app_extension, "FinderXXMindThumbnailExtension", :osx, "14.0")
configure_common(thumbnail_extension, "dev.finderx.FinderX.XMindThumbnailExtension")
add_sources(project, thumbnail_extension, "Sources", ["Sources/FinderXXMindThumbnailExtension/ThumbnailProvider.swift"])
link_framework(thumbnail_extension, xmind_preview_core)
thumbnail_extension.build_configurations.each do |config|
  config.build_settings["INFOPLIST_FILE"] = "FinderXXMindThumbnailExtension/Resources/Info.plist"
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "FinderXXMindThumbnailExtension/Resources/FinderXXMindThumbnailExtension.entitlements"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks"
  config.build_settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
  config.build_settings["ENABLE_USER_SELECTED_FILES"] = "readonly"
end
thumbnail_extension_file = embed_extensions.add_file_reference(thumbnail_extension.product_reference)
thumbnail_extension_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
app.add_dependency(thumbnail_extension)

preview_extension = project.new_target(:app_extension, "FinderXXMindPreviewExtension", :osx, "14.0")
configure_common(preview_extension, "dev.finderx.FinderX.XMindPreviewExtension")
add_sources(project, preview_extension, "Sources", ["Sources/FinderXXMindPreviewExtension/PreviewProvider.swift"])
link_framework(preview_extension, xmind_preview_core)
preview_extension.build_configurations.each do |config|
  config.build_settings["INFOPLIST_FILE"] = "FinderXXMindPreviewExtension/Resources/Info.plist"
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "FinderXXMindPreviewExtension/Resources/FinderXXMindPreviewExtension.entitlements"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks"
  config.build_settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
  config.build_settings["ENABLE_USER_SELECTED_FILES"] = "readonly"
end
preview_extension_file = embed_extensions.add_file_reference(preview_extension.product_reference)
preview_extension_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
app.add_dependency(preview_extension)

cli = project.new_target(:command_line_tool, "FinderXCompressCLI", :osx, "14.0")
configure_common(cli, "dev.finderx.FinderXCompressCLI")
add_sources(project, cli, "Sources", ["Sources/FinderXCompressCLI/main.swift"])
link_framework(cli, core)
embed_framework(cli, core)
cli.build_configurations.each do |config|
  config.build_settings["PRODUCT_NAME"] = "finderx-compress"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../Frameworks @executable_path"
end

tests = project.new_target(:unit_test_bundle, "ImageCompressionCoreTests", :osx, "14.0")
configure_common(tests, "dev.finderx.ImageCompressionCoreTests")
add_sources(project, tests, "Tests", ["Tests/ImageCompressionCoreTests/ImageCompressionCoreTests.swift"])
link_framework(tests, core)
tests.build_configurations.each do |config|
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @loader_path/Frameworks @loader_path/../Frameworks"
end

link_tests = project.new_target(:unit_test_bundle, "FinderXLinkingTests", :osx, "14.0")
configure_common(link_tests, "dev.finderx.FinderXLinkingTests")
add_sources(project, link_tests, "Tests", ["Tests/FinderXLinkingTests/FinderXLinkingTests.swift"])
link_framework(link_tests, linking)
link_tests.build_configurations.each do |config|
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @loader_path/Frameworks @loader_path/../Frameworks"
end

xmind_preview_tests = project.new_target(:unit_test_bundle, "XMindPreviewCoreTests", :osx, "14.0")
configure_common(xmind_preview_tests, "dev.finderx.XMindPreviewCoreTests")
add_sources(project, xmind_preview_tests, "Tests", ["Tests/XMindPreviewCoreTests/XMindPreviewCoreTests.swift"])
link_framework(xmind_preview_tests, xmind_preview_core)
xmind_preview_tests.build_configurations.each do |config|
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @loader_path/Frameworks @loader_path/../Frameworks"
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(extension)
scheme.add_build_target(thumbnail_extension)
scheme.add_build_target(preview_extension)
scheme.add_build_target(cli)
scheme.add_test_target(tests)
scheme.add_test_target(link_tests)
scheme.add_test_target(xmind_preview_tests)
scheme.set_launch_target(app)
scheme.save_as(PROJECT_PATH, "FinderX", true)

project.save
