# frozen_string_literal: true

require "json"

module OKF
  class Bundle
    # Disk cache for the minimal graph payload (nodes, edges, types, tags,
    # edge_cut). Lives at <bundle-root>/.okf-cache/graph.json alongside the
    # layout cache. Invalidated by a fingerprint — the maximum mtime across
    # every .md file in the bundle root (recursive). A single file edit bumps
    # the fingerprint and the next /graphdata request rebuilds and re-saves.
    #
    # The cache directory is created on first write. A cache file that cannot
    # be read or whose fingerprint does not match is treated as a miss — the
    # server continues without it. A write error is silently ignored: a cache
    # miss on every request is worse than no cache at all, but it is not a
    # server error.
    #
    # Part of the shell: reads and writes the filesystem.
    class GraphCache
      DIR  = ".okf-cache"
      FILE = "graph.json"

      def initialize(root)
        @root      = root
        @cache_dir = File.join(root, DIR)
        @path      = File.join(@cache_dir, FILE)
      end

      # Fingerprint of the bundle on disk: the max mtime (integer seconds)
      # across every .md file under the root. Returns 0 if no .md files exist.
      def fingerprint
        @fingerprint ||= begin
          mtimes = Dir.glob(File.join(@root, "**", "*.md")).map { |f| File.mtime(f).to_i rescue 0 }
          mtimes.empty? ? 0 : mtimes.max
        end
      end

      # Read from cache. Returns the parsed payload hash if the cache is valid,
      # or nil on a miss (missing file, bad JSON, stale fingerprint).
      def read
        return nil unless File.exist?(@path)

        raw = File.read(@path, encoding: "UTF-8")
        cached = JSON.parse(raw)
        return nil unless cached["fingerprint"] == fingerprint

        cached["payload"]
      rescue StandardError
        nil
      end

      # Write +payload+ to cache alongside its fingerprint. Silent on error.
      def write(payload)
        FileUtils.mkdir_p(@cache_dir)
        tmp = "#{@path}.tmp.#{Process.pid}"
        File.write(tmp, JSON.generate({ "fingerprint" => fingerprint, "payload" => payload }), encoding: "UTF-8")
        File.rename(tmp, @path)
      rescue StandardError
        nil
      end
    end
  end
end
