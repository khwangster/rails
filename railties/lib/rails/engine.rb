require 'active_support/core_ext/module/delegation'

module Rails
  # TODO Move I18n and views path setup
  class Engine < Railtie

    class << self
      attr_accessor :called_from

      def root
        @root ||= find_root_with_file_flag("lib")
      end

      def config
        @config ||= Configuration.new(root)
      end

      def inherited(base)
        base.called_from = begin
          call_stack = caller.map { |p| p.split(':').first }
          File.dirname(call_stack.detect { |p| p !~ %r[railties/lib/rails|rack/lib/rack] })
        end
        super
      end

    protected

      def find_root_with_file_flag(flag, default=nil)
        root_path = self.called_from

        while root_path && File.directory?(root_path) && !File.exist?("#{root_path}/#{flag}")
          parent = File.dirname(root_path)
          root_path = parent != root_path && parent
        end

        root = File.exist?("#{root_path}/flag") ? root_path : default

        raise "Could not find root path for #{self}" unless root

        RUBY_PLATFORM =~ /(:?mswin|mingw)/ ?
          Pathname.new(root).expand_path :
          Pathname.new(root).realpath
      end
    end

    delegate :root, :config, :to => :'self.class'
    delegate :middleware,    :to => :config

    # Add configured load paths to ruby load paths and remove duplicates.
    initializer :set_load_path, :before => :container do
      config.paths.add_to_load_path
      $LOAD_PATH.uniq!
    end

    # Set the paths from which Rails will automatically load source files,
    # and the load_once paths.
    initializer :set_autoload_paths, :before => :container do
      require 'active_support/dependencies'

      ActiveSupport::Dependencies.load_paths = expand_load_path(config.load_paths)
      ActiveSupport::Dependencies.load_once_paths = expand_load_path(config.load_once_paths)

      extra = ActiveSupport::Dependencies.load_once_paths - ActiveSupport::Dependencies.load_paths

      unless extra.empty?
        abort <<-end_error
          load_once_paths must be a subset of the load_paths.
          Extra items in load_once_paths: #{extra * ','}
        end_error
      end

      # Freeze the arrays so future modifications will fail rather than do nothing mysteriously
      config.load_once_paths.freeze
    end

    initializer :load_application_initializers do
      Dir["#{root}/config/initializers/**/*.rb"].sort.each do |initializer|
        load(initializer)
      end
    end

    # Routing must be initialized after plugins to allow the former to extend the routes
    initializer :initialize_routing do |app|
      app.route_configuration_files.concat(config.paths.config.routes.to_a)
    end

    # Eager load application classes
    initializer :load_application_classes do |app|
      next if $rails_rake_task

      if app.config.cache_classes
        config.eager_load_paths.each do |load_path|
          matcher = /\A#{Regexp.escape(load_path)}(.*)\.rb\Z/
          Dir.glob("#{load_path}/**/*.rb").sort.each do |file|
            require_dependency file.sub(matcher, '\1')
          end
        end
      end
    end

  private

    def expand_load_path(load_paths)
      load_paths.map { |path| Dir.glob(path.to_s) }.flatten.uniq
    end
  end
end