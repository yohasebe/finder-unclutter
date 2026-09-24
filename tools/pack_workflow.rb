#!/usr/bin/env ruby
# frozen_string_literal: true

# Build the distribution bundle from an explicit allowlist.
#
#   ruby tools/pack_workflow.rb            # check only
#   ruby tools/pack_workflow.rb --write    # check, then write the bundle
#
# `python3 tools/build.py --package` injects source/scripts/ into
# source/info.plist, lints it, and then calls this script with --write. This is
# the only place that decides what goes into the .alfredworkflow; build.py does
# not keep a second copy of the rule.
#
# Why not Alfred's GUI export: it puts everything in the workflow directory
# except prefs.plist into the zip. Anything a run leaves behind ships -- logs,
# recordings, editor backups. This repository's 2025-09-22 release went out
# with an `info.plist.bak` in it that way, and the history had to be rewritten
# to get it out again. "Look at the folder before exporting" is not a control.
#
# The check runs in BOTH directions, and either one failing stops the build:
#
#   listed but missing  -> we would ship an incomplete workflow
#   present but unknown -> we would ship something nobody decided to ship
#
# One direction is not enough. This workflow shipped 54 files with its icon.png
# deleted and no error, because a workflow without an icon installs fine and
# nothing complained.
#
# Fixed content is listed by name. Only the places where Alfred generates the
# names are matched by pattern: it writes `<object-uid>.png` beside the
# workflow when a node is given an icon, so "every png at the root" would be
# the wrong rule -- it would wave through a screenshot dropped into source/.

require "fileutils"
require "json"
require "tmpdir"

REPO = File.expand_path("..", __dir__)
# The source of truth is source/ in the repository, not the installed
# workflow directory: build.py generates
# source/info.plist and copies it outwards with --install. Verified 2026-09-08
# that the two are byte-identical apart from scripts/ and prefs.plist.
WF = ENV["FINDER_UNCLUTTER_SOURCE_DIR"] || File.join(REPO, "source")
BUNDLE = File.join(REPO, "finder-unclutter.alfredworkflow")

# --- the allowlist ----------------------------------------------------------

NAMED = %w[
  info.plist
  icon.png
  finder-unclutter@2x.png
].freeze

# Alfred generates these names; they cannot be listed. A name of the right
# shape is not enough on its own, though -- see REFERENCED below.
GENERATED = [
  /\A[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.png\z/,
  %r{\AList Filter Images/[^/]+\.png\z}
].freeze

# Deliberately never shipped. Named so that finding one is not a surprise.
EXCLUDED = ["prefs.plist"].freeze
# scripts/ is the AppleScript source. build.py injects each file's body into
# the Run Script objects of info.plist, so shipping the directory as well would
# put a second copy in the bundle that can silently disagree with the one
# Alfred actually runs.
EXCLUDED_TREES = ["scripts/"].freeze

# --- gather -----------------------------------------------------------------

# The generated names are only allowed when info.plist actually uses them: an
# icon beside the workflow must belong to one of its objects, and a List Filter
# image must be named by one of the list items. A pattern alone would ship any
# png dropped there -- a screenshot taken while testing, say -- and Alfred never
# deletes an image when the item that used it goes away, which is how 32 unused
# images rode along in every release up to 2.0.
def referenced_names(plist_path)
  return [] unless File.file?(plist_path)
  json = IO.popen(["plutil", "-convert", "json", "-o", "-", plist_path], &:read)
  abort "cannot read #{File.basename(plist_path)} with plutil" unless $?.success?
  objects = JSON.parse(json).fetch("objects", [])
  icons = objects.map { |o| "#{o["uid"]}.png" }
  images = objects.flat_map do |o|
    items = o.dig("config", "items")
    next [] unless items
    items = items.join if items.is_a?(Array)
    JSON.parse(items).map { |i| i["imagefile"] }.compact.map { |n| "List Filter Images/#{n}" }
  end
  icons + images
end

REFERENCED = referenced_names(File.join(WF, "info.plist")).freeze

on_disk = Dir.glob("#{WF}/**/*", File::FNM_DOTMATCH)
          .select { |p| File.file?(p) }
          .map { |p| p.sub("#{WF}/", "") }
          .sort

generated    = on_disk.select { |f| GENERATED.any? { |re| f =~ re } }
unreferenced = generated - REFERENCED
allowed      = on_disk.select { |f| NAMED.include?(f) } + (generated & REFERENCED)
excluded     = on_disk.select { |f| EXCLUDED.include?(f) || EXCLUDED_TREES.any? { |d| f.start_with?(d) } }
unknown      = on_disk - allowed - excluded - unreferenced
# The other direction for List Filter images: an item naming an image that is
# not there shows no icon, and nothing complains. (Object icons are optional --
# only nodes given an icon have one -- so they are not required.)
missing  = NAMED - on_disk + (REFERENCED.select { |f| f.start_with?("List Filter Images/") } - on_disk)

puts "workflow folder: #{on_disk.length} files (#{WF})"
puts "  to ship:  #{allowed.length}"
puts "  excluded: #{excluded.length}"
puts

problems = false

unless missing.empty?
  puts "LISTED BUT MISSING (#{missing.length}) - the bundle would be incomplete:"
  missing.each { |f| puts "  #{f}" }
  puts
  problems = true
end

unless unknown.empty?
  puts "PRESENT BUT UNKNOWN (#{unknown.length}) - nobody decided to ship these:"
  unknown.each { |f| puts "  #{f}" }
  puts "  Either delete them from source/, or add them to the allowlist in"
  puts "  this script if they genuinely belong in the release."
  puts
  problems = true
end

unless unreferenced.empty?
  puts "NAMED LIKE ALFRED'S BUT UNUSED (#{unreferenced.length}) - info.plist does not refer to these:"
  unreferenced.each { |f| puts "  #{f}" }
  puts "  Alfred leaves images behind when an item stops using them; delete them."
  puts
  problems = true
end

# A last look inside, independent of the lists above.
suspicious = allowed.select do |f|
  f =~ /\.(log|mp3|wav|m4a|webm|bak|orig|tmp)\z/i || f =~ %r{(\A|/)(tags|\.DS_Store|data\.json)\z}
end
unless suspicious.empty?
  puts "ALLOWLISTED BUT SUSPICIOUS (#{suspicious.length}): #{suspicious.inspect}"
  problems = true
end

# Alfred's export excludes exactly one name, prefs.plist. That is a denylist of
# length one: a second file holding a key would ship. An allowlist already
# refuses anything unrecognised, but the files we *do* ship are worth reading -
# a key pasted into a script would pass every check above, and info.plist here
# carries the body of every AppleScript in the workflow.
SECRETS = /sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|github_pat_|BEGIN (RSA |OPENSSH )?PRIVATE KEY|xox[baprs]-/.freeze
leaking = allowed.select do |f|
  next false if f =~ /\.(png|woff2|icns)\z/i   # binary, and not where a key hides
  File.binread(File.join(WF, f)) =~ SECRETS
end
unless leaking.empty?
  puts "SECRET-SHAPED STRINGS in files we would ship (#{leaking.length}):"
  leaking.each { |f| puts "  #{f}" }
  problems = true
end

# And the local-environment traces that should not travel either: a home
# directory, the per-user temporary area macOS hands out under /private/var/
# folders (it is also reachable as /var/folders), and anything under a
# dot-directory in the home folder, where tools keep their own settings.
TRACES = %r{/Users/[a-z]|/private/|/var/folders/|~/\.}i.freeze
traces = allowed.select do |f|
  next false if f =~ /\.(png|woff2|icns)\z/i
  File.binread(File.join(WF, f)) =~ TRACES
end
unless traces.empty?
  puts "LOCAL PATHS in files we would ship (#{traces.length}): #{traces.inspect}"
  problems = true
end

if problems
  puts "Refusing to build."
  exit 1
end

puts "Allowlist agrees with the folder in both directions."

exit 0 unless ARGV.include?("--write")

# --- build ------------------------------------------------------------------

tmp = File.join(Dir.tmpdir, "pack-#{Process.pid}.zip")
File.delete(tmp) if File.exist?(tmp)
# Alfred's own export writes a directory entry for each directory it ships.
# Extractors do not need them, but matching the structure of the artefact
# Alfred produces keeps this bundle from being the odd one out.
dirs = allowed.map { |f| File.dirname(f) }
              .reject { |d| d == "." }
              .flat_map { |d| d.split("/").each_with_object([]) { |part, acc| acc << (acc.empty? ? part : "#{acc.last}/#{part}") } }
              .uniq.sort.map { |d| "#{d}/" }

Dir.chdir(WF) do
  # -X drops extra attributes so the zip is reproducible between machines.
  args = ["zip", "-X", "-q", tmp] + dirs + allowed
  system(*args) or abort "zip failed"
end

# Verify what was actually written, rather than trusting the command.
written = `unzip -Z1 "#{tmp}"`.lines.map(&:chomp).reject(&:empty?).sort
if written != (dirs + allowed).sort
  puts "the zip does not contain what we asked for:"
  puts "  only in zip:    #{(written - dirs - allowed).inspect}"
  puts "  missing in zip: #{((dirs + allowed) - written).inspect}"
  File.delete(tmp)
  exit 1
end

Dir.mktmpdir do |dir|
  system("unzip", "-q", "-o", tmp, "-d", dir, out: File::NULL) or abort "unzip failed"
  differing = allowed.reject do |f|
    File.binread(File.join(WF, f)) == File.binread(File.join(dir, f))
  end
  unless differing.empty?
    puts "content differs from the folder: #{differing.inspect}"
    File.delete(tmp)
    exit 1
  end
end

FileUtils.mv(tmp, BUNDLE)
puts "wrote #{File.basename(BUNDLE)} (#{allowed.length} entries, #{File.size(BUNDLE)} bytes)"
