require 'digest/md5'

#
# Want to write your own package?
#
# Check Rip::PackageAPI for the methods you need.
#

module Rip
  class Package
    include PackageAPI, Memoize

    attr_reader :source
    def initialize(source, version = nil, files = nil)
      @source = source.strip.chomp
      @version = version
      @files = files
    end

    @@patterns = {}
    @@blocks = {}

    def self.handles(*patterns, &block)
      patterns.each do |pattern|
        @@patterns[pattern] = self
      end

      @@blocks[self] = block if block
    end

    def self.for(source, *args)
      source = source.strip.chomp

      handler = @@patterns.detect do |pattern, klass|
        case pattern
        when String
          if pattern[0,1] == '.'
            pattern = Regexp.escape(pattern)
            source.match Regexp.new("#{pattern}$")
          else
            source.include? pattern
          end
        else
          source.match(pattern)
        end
      end

      return handler[1].new(source, *args) if handler

      handler = @@blocks.detect do |klass, block|
        block.call(source)
      end

      return handler[0].new(source, *args) if handler
    end

    def to_s
      version ? "#{name} (#{version})" : name.to_s
    end

    memoize :cache_name
    def cache_name
      name + '-' + Digest::MD5.hexdigest(@source)
    end

    memoize :cache_path
    def cache_path
      File.join(packages_path, cache_name)
    end

    memoize :packages_path
    def packages_path
      File.join(Rip.dir, 'rip-packages')
    end

    def installed?
      graph = PackageManager.new
      graph.installed?(name) && graph.package_version(name) == version
    end

    def fetch
      return if @fetched
      fetch!
      @fetched = true
    end

    def unpack
      return if @unpacked
      unpack!
      @unpacked = true
    end

    def files
      @files ||= files!
    end

    def files!
      fetch
      unpack

      Dir.chdir cache_path do
        Dir['lib/**/*'] + Dir['bin/**/*']
      end
    end
    attr_writer :files

    def dependencies
      @dependencies ||= dependencies!
    end

    def dependencies!
      if File.exists? deps = File.join(cache_path, 'deps.rip')
        File.readlines(deps).map do |line|
          source, version, *extra = line.split(' ')
          Package.for(source, version)
        end
      else
        []
      end
    end

    def run_hook(hook, *args, &block)
      send(hook, *args, &block) if respond_to? hook
    end

    def ui
      Rip.ui
    end
  end
end
