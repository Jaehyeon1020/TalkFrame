# frozen_string_literal: true

require "cask/cask_loader"
require "cask/download"
require "json"

cask = Cask::CaskLoader::FromContentLoader.new(File.read(ARGV.fetch(0))).load(config: nil)
raise "unexpected token" unless cask.token == "talkframe"
metadata = JSON.parse(cask.to_h.to_json)
raise "authentication/custom downloader must not be configured" unless metadata.fetch("url_specs").empty?
raise "unexpected download strategy" unless Cask::Download.new(cask).downloader.instance_of?(CurlDownloadStrategy)
raise "unexpected artifact" unless metadata.fetch("artifacts").first.fetch("app").first == "TalkFrame.app"
raise "unexpected dependency" unless metadata.fetch("depends_on").keys == ["macos"]
puts "PASS Homebrew Cask evaluation, standard unauthenticated downloader, app artifact and macOS requirement"
