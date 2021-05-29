require "set"
require "securerandom"

module Zeitwerk::Loader::Config
  # Absolute paths of the root directories. Stored in a hash to preserve
  # order, easily handle duplicates, and also be able to have a fast lookup,
  # needed for detecting nested paths.
  #
  #   "/Users/fxn/blog/app/assets"   => true,
  #   "/Users/fxn/blog/app/channels" => true,
  #   ...
  #
  # This is a private collection maintained by the loader. The public
  # interface for it is `push_dir` and `dirs`.
  #
  # @private
  # @sig Hash[String, true]
  attr_reader :root_dirs

  # @sig #camelize
  attr_accessor :inflector

  # Absolute paths of files, directories, or glob patterns to be totally
  # ignored.
  #
  # @private
  # @sig Set[String]
  attr_reader :ignored_glob_patterns

  # The actual collection of absolute file and directory names at the time the
  # ignored glob patterns were expanded. Computed on setup, and recomputed on
  # reload.
  #
  # @private
  # @sig Set[String]
  attr_reader :ignored_paths

  # Absolute paths of directories or glob patterns to be collapsed.
  #
  # @private
  # @sig Set[String]
  attr_reader :collapse_glob_patterns

  # The actual collection of absolute directory names at the time the collapse
  # glob patterns were expanded. Computed on setup, and recomputed on reload.
  #
  # @private
  # @sig Set[String]
  attr_reader :collapse_dirs

  # Absolute paths of files or directories not to be eager loaded.
  #
  # @private
  # @sig Set[String]
  attr_reader :eager_load_exclusions

  # User-oriented callbacks to be fired when a constant is loaded.
  #
  # @private
  # @sig Hash[String, Array[{ () -> void }]]
  attr_reader :on_load_callbacks

  # @sig #call | #debug | nil
  attr_accessor :logger

  # This is useful in order to be able to distinguish loaders in logging.
  #
  # @sig String
  attr_accessor :tag

  def initialize
    @initialized_at         = Time.now
    @root_dirs              = {}
    @inflector              = Zeitwerk::Inflector.new
    @ignored_glob_patterns  = Set.new
    @ignored_paths          = Set.new
    @collapse_glob_patterns = Set.new
    @collapse_dirs          = Set.new
    @eager_load_exclusions  = Set.new
    @reloading_enabled      = false
    @on_load_callbacks      = Hash.new { |h, cpath| h[cpath] = [] }
    @logger                 = self.class.default_logger
    @tag                    = SecureRandom.hex(3)
  end

  # Pushes `path` to the list of root directories.
  #
  # Raises `Zeitwerk::Error` if `path` does not exist, or if another loader in
  # the same process already manages that directory or one of its ascendants or
  # descendants.
  #
  # @raise [Zeitwerk::Error]
  # @sig (String | Pathname, Module) -> void
  def push_dir(path, namespace: Object)
    # Note that Class < Module.
    unless namespace.is_a?(Module)
      raise Zeitwerk::Error, "#{namespace.inspect} is not a class or module object, should be"
    end

    abspath = File.expand_path(path)
    if dir?(abspath)
      raise_if_conflicting_directory(abspath)
      root_dirs[abspath] = namespace
    else
      raise Zeitwerk::Error, "the root directory #{abspath} does not exist"
    end
  end

  # Sets a tag for the loader, useful for logging.
  #
  # @param tag [#to_s]
  # @sig (#to_s) -> void
  def tag=(tag)
    @tag = tag.to_s
  end

  # Absolute paths of the root directories. This is a read-only collection,
  # please push here via `push_dir`.
  #
  # @sig () -> Array[String]
  def dirs
    root_dirs.keys.freeze
  end

  # You need to call this method before setup in order to be able to reload.
  # There is no way to undo this, either you want to reload or you don't.
  #
  # @raise [Zeitwerk::Error]
  # @sig () -> void
  def enable_reloading
    mutex.synchronize do
      break if @reloading_enabled

      if @setup
        raise Zeitwerk::Error, "cannot enable reloading after setup"
      else
        @reloading_enabled = true
      end
    end
  end

  # @sig () -> bool
  def reloading_enabled?
    @reloading_enabled
  end

  # Let eager load ignore the given files or directories. The constants defined
  # in those files are still autoloadable.
  #
  # @sig (*(String | Pathname | Array[String | Pathname])) -> void
  def do_not_eager_load(*paths)
    mutex.synchronize { eager_load_exclusions.merge(expand_paths(paths)) }
  end

  # Configure files, directories, or glob patterns to be totally ignored.
  #
  # @sig (*(String | Pathname | Array[String | Pathname])) -> void
  def ignore(*glob_patterns)
    glob_patterns = expand_paths(glob_patterns)
    mutex.synchronize do
      ignored_glob_patterns.merge(glob_patterns)
      ignored_paths.merge(expand_glob_patterns(glob_patterns))
    end
  end

  # Configure directories or glob patterns to be collapsed.
  #
  # @sig (*(String | Pathname | Array[String | Pathname])) -> void
  def collapse(*glob_patterns)
    glob_patterns = expand_paths(glob_patterns)
    mutex.synchronize do
      collapse_glob_patterns.merge(glob_patterns)
      collapse_dirs.merge(expand_glob_patterns(glob_patterns))
    end
  end

  # Configure a block to be invoked once a certain constant path is loaded.
  # Supports multiple callbacks, and if there are many, they are executed in
  # the order in which they were defined.
  #
  #   loader.on_load("SomeApiClient") do
  #     SomeApiClient.endpoint = "https://api.dev"
  #   end
  #
  # @raise [TypeError]
  # @sig (String) { () -> void } -> void
  def on_load(cpath, &block)
    raise TypeError, "on_load only accepts strings" unless cpath.is_a?(String)

    mutex.synchronize do
      on_load_callbacks[cpath] << block
    end
  end

  # Logs to `$stdout`, handy shortcut for debugging.
  #
  # @sig () -> void
  def log!
    @logger = ->(msg) { puts msg }
  end

  # @private
  # @sig (String) -> bool
  def manages?(dir)
    dir = dir + "/"
    ignored_paths.each do |ignored_path|
      return false if dir.start_with?(ignored_path + "/")
    end

    root_dirs.each_key do |root_dir|
      return true if root_dir.start_with?(dir) || dir.start_with?(root_dir + "/")
    end

    false
  end

  private

  # @sig () -> Array[String]
  def actual_root_dirs
    root_dirs.reject do |root_dir, _namespace|
      !dir?(root_dir) || ignored_paths.member?(root_dir)
    end
  end

  # @sig (String) -> bool
  def root_dir?(dir)
    root_dirs.key?(dir)
  end

  # @sig (String) -> bool
  def excluded_from_eager_load?(abspath)
    eager_load_exclusions.member?(abspath)
  end

  # @sig (String) -> bool
  def collapse?(dir)
    collapse_dirs.member?(dir)
  end

  # @sig (String | Pathname | Array[String | Pathname]) -> Array[String]
  def expand_paths(paths)
    paths.flatten.map! { |path| File.expand_path(path) }
  end

  # @sig (Array[String]) -> Array[String]
  def expand_glob_patterns(glob_patterns)
    # Note that Dir.glob works with regular file names just fine. That is,
    # glob patterns technically need no wildcards.
    glob_patterns.flat_map { |glob_pattern| Dir.glob(glob_pattern) }
  end

  # @sig () -> void
  def recompute_ignored_paths
    ignored_paths.replace(expand_glob_patterns(ignored_glob_patterns))
  end

  # @sig () -> void
  def recompute_collapse_dirs
    collapse_dirs.replace(expand_glob_patterns(collapse_glob_patterns))
  end
end
