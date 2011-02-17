# Copyright (C) 2011  Kouhei Sutou <kou@clear-code.com>
#
# This library is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this library.  If not, see <http://www.gnu.org/licenses/>.

require 'pathname'

module Milter
  class Client
    class Configuration
      class InvalidValue < Error
        def initialize(target, available_values, actual_value)
          @target = target
          @available_values = available_values
          @actual_value = actual_value
          super("#{@target} should be one of #{@available_values.inspect} " +
                "but was #{@actual_value.inspect}")
        end
      end

      class NonexistentPath < Error
        def initialize(path)
          @path = path
          super("#{@path} doesn't exist.")
        end
      end

      class MissingValue < Error
        def initialize(target)
          @target = target
          super("#{@target} should be set")
        end
      end

      attr_reader :milter, :database, :load_paths, :prefix
      def initialize
        clear
      end

      def clear
        @milter = MilterConfiguration.new(self)
        @database = DatabaseConfiguration.new(self)
        @load_paths = []
        @locations = {}
        @prefix = nil
      end

      def setup(client)
        @milter.setup(client)
        @database.setup(client)
      end

      def resolve_path(path)
        return [path] if Pathname(path).absolute?
        @load_paths.collect do |load_path|
          full_path = File.join(load_path, path)
          if File.directory?(full_path)
            Dir.open(full_path) do |dir|
              dir.each do |sub_path|
                next if sub_path == "." or sub_path == ".."
                full_sub_path = File.join(full_path, sub_path)
                next if File.directory?(full_sub_path)
                paths << full_sub_path
              end
            end
            return paths
          elsif File.exist?(full_path)
            return [full_path]
          else
            Dir.glob(full_path).reject do |expanded_full_path|
              File.directory?(expanded_full_path)
            end
          end
        end.flatten
      end

      def expand_path(path)
        return path if Pathname(path).absolute?
        if @prefix
          File.join(@prefix, path)
        else
          path
        end
      end

      def update_location(key, reset, deep_level)
        if reset
          @locations.delete(key)
        else
          file, line, _ = caller[deep_level].split(/:/, 3)
          @locations[key] = [file, line.to_i]
        end
      end

      class MilterConfiguration
        attr_accessor :name, :connection_spec, :user, :group
        attr_accessor :unix_socket_mode, :unix_socket_group
        attr_accessor :remove_unix_socket_on_create
        attr_accessor :remove_unix_socket_on_close
        attr_accessor :pid_file, :maintenance_interval
        attr_accessor :suspend_time_on_unacceptable, :max_connections
        attr_accessor :max_file_descriptors, :event_loop_backend
        attr_accessor :n_workers, :packet_buffer_size
        attr_accessor :syslog_facility, :status_on_error
        attr_writer :daemon, :handle_signal, :run_gc_on_maintain, :use_syslog
        def initialize(base_configuration)
          @base_configuration = base_configuration
          clear
        end

        def daemon?
          @daemon
        end

        def handle_signal?
          @handle_signal
        end

        def run_gc_on_maintain?
          @run_gc_on_maintain
        end

        def use_syslog?
          @use_syslog
        end

        def clear
          @name = File.basename($PROGRAM_NAME, ".*"),
          @connection_spec = "inet:20025"
          @user = nil
          @group = nil
          @unix_socket_mode = 0770
          @unix_socket_group = nil
          @remove_unix_socket_on_create = true
          @remove_unix_socket_on_close = true
          @daemon = false
          @pid_file = nil
          @maintenance_interval = 100
          @suspend_time_on_unacceptable =
            Milter::Client::DEFAULT_SUSPEND_TIME_ON_UNACCEPTABLE
          @max_connections = Milter::Client::DEFAULT_MAX_CONNECTIONS
          @max_file_descriptors = 0
          @event_loop_backend = Milter::Client::EVENT_LOOP_BACKEND_GLIB.nick
          @n_workers = 0
          @packet_buffer_size = 0
          @run_gc_on_maintain = true
          @use_syslog = false
          @syslog_facility = "mail"
          @handle_signal = true
          @maintained_hooks = []
        end

        def setup(client)
          client.start_syslog(@name, @syslog_facility) if @use_syslog
          client.status_on_error = @status_on_error
          client.connection_spec = @connection_spec
          client.effective_user = @user
          client.effective_group = @group
          client.unix_socket_group = @unix_socket_group
          client.unix_socket_mode = @unix_socket_mode if @unix_socket_mode
          client.event_loop_backend = @event_loop_backend
          client.default_packet_buffer_size = @packet_buffer_size
          client.maintenance_interval = @maintenance_interval
          if @run_gc_on_maintain
            client.on_maintain do
              GC.start
            end
          end
          client.n_workers = @n_workers
          unless @maintained_hooks.empty?
            client.on_maintain do
              @maintained_hooks.each do |hook|
                hook.call
              end
            end
          end
        end

        def update_location(key, reset, deep_level)
          @base_configuration.update_location(key, reset, deep_level + 1)
        end
      end

      class DatabaseConfiguration
        attr_accessor :type, :name, :host, :port, :path
        attr_accessor :user, :password
        def initialize(base_configuration)
          @base_configuration = base_configuration
          clear
        end

        def clear
          @setup_done = false
          @type = nil
          @name = nil
          @host = nil
          @port = nil
          @path = nil
          @user = nil
          @password = nil
        end

        def setup(key_prefix="database.")
          return if @setup_done
          return if @type.nil?
          case @type
          when "mysql", "mysql2"
            options = mysql_options(key_prefix)
          when "sqlite3"
            options = sqlite3_options(key_prefix)
          else
            options = default_options(key_prefix)
          end
          Milter::Logger.info("[configuration][database][setup] " +
                              "<#{options.inspect}>")
          require 'active_record'
          logger = Milter::ActiveRecordLogger.new(Milter::Logger.default)
          ActiveRecord::Base.logger = logger
          ActiveRecord::Base.establish_connection(options)
          @setup_done = true
        end

        def to_hash
          {
            :type => type,
            :name => name,
            :host => host,
            :port => port,
            :path => path,
            :user => user,
            :password => password,
          }
        end

        def update_location(key, reset, deep_level)
          @base_configuration.update_location(key, reset, deep_level + 1)
        end

        private
        def mysql_options(key_prefix)
          options = {}
          options[:adapter] = @type
          raise MissingValue.new("#{key_prefix}name") if @name.nil?
          options[:database] = @name
          options[:host] = @host || "localhost"
          options[:port] = @port || 3306
          default_path = "/var/run/mysqld/mysqld.sock"
          default_path = nil unless File.exist?(default_path)
          options[:path] = @path || default_path
          options[:username] = @user || "root"
          options[:password] = @password
          options
        end

        def sqlite3_options(key_prefix)
          options = {}
          options[:adapter] = @type
          options[:database] = @name || @path
          unless options[:database] == ":memory:"
            options[:database] = expand_path(options[:database])
          end
          options
        end

        def default_options(key_prefix)
          options = to_hash
          options[:adapter] = options.delete(:type)
          options[:database] = options.delete(:name)
          options[:username] = options.delete(:user)
          options
        end

        def expand_path(path)
          @base_configuration.expand_path(path)
        end
      end
    end

    class ConfigurationLoader
      attr_reader :milter, :database
      def initialize(configuration)
        @configuration = configuration
        @milter = MilterConfigurationLoader.new(@configuration.milter)
        @database = DatabaseConfigurationLoader.new(@configuration.database)
        @depth = 0
      end

      def load(path)
        resolved_paths = @configuration.resolve_path(path)
        raise ConfigurationNonexistentPath.new(path) if resolved_paths.empty?
        resolved_paths.each do |resolved_path|
          load_path(resolved_path)
        end
      end

      def load_if_exist(path)
        load(path)
      rescue NonexistentPath
        Milter::Logger.debug("[configuration][load][nonexistent][ignore] " +
                             "<#{path}>")
      end

      def guard(fallback_value=nil)
        yield
      rescue Exception => error
        Milter::Logger.error(error)
        fallback_value
      end

      private
      def load_path(path)
        begin
          content = File.read(path)
          Milter::Logger.debug("[configuration][load][start] <#{path}>")
          instance_eval(content, path)
        rescue Configuration::InvalidValue
          backtrace = $!.backtrace.collect do |info|
            if /\A#{Regexp.escape(path)}:/ =~ info
              info
            else
              nil
            end
          end.compact
          Milter::Logger.error("#{backtrace[0]}: #{$!.message}")
          Milter::Logger.error(backtrace[1..-1].join("\n"))
        ensure
          Milter::Logger.debug("[configuration][load][end] <#{path}>")
        end
      end

      class MilterConfigurationLoader
        def initialize(configuration)
          @configuration = configuration
        end

        def connection_spec
          @configuration.connection_spec
        end

        def connection_spec=(spec)
          Milter::Connection.parse_spec(spec) unless spec.nil?
          update_location("connection_spec", spec.nil?)
          @configuration.connection_spec = spec
        end

        def unix_socket_mode
          @configuration.unix_socket_mode
        end

        def unix_socket_mode=(mode)
          update_location("unix_socket_mode", false)
          @configuration.unix_socket_mode = mode
        end

        def unix_socket_group
          @configuration.unix_socket_group
        end

        def unix_socket_group=(group)
          update_location("unix_socket_group", group.nil?)
          @configuration.unix_socket_group = group
        end

        def remove_unix_socket_on_create?
          @configuration.remove_unix_socket_on_create?
        end

        def remove_unix_socket_on_create=(remove)
          update_location("remove_unix_socket_on_create", false)
          @configuration.remove_unix_socket_on_create = remove
        end

        def remove_unix_socket_on_close?
          @configuration.remove_unix_socket_on_close?
        end

        def remove_unix_socket_on_close=(remove)
          update_location("remove_unix_socket_on_close", false)
          @configuration.remove_unix_socket_on_close = remove
        end

        def daemon=(boolean)
          update_location("daemon", false)
          @configuration.daemon = boolean
        end

        def daemon?
          @configuration.daemon?
        end

        def pid_file=(pid_file)
          update_location("pid_file", pid_file.nil?)
          @configuration.pid_file = pid_file
        end

        def pid_file
          @configuration.pid_file
        end

        def maintenance_interval=(n_sessions)
          update_location("maintenance_interval", n_sessions.nil?)
          n_sessions ||= 0
          @configuration.maintenance_interval = n_sessions
        end

        def maintenance_interval
          @configuration.maintenance_interval
        end

        def suspend_time_on_unacceptable=(seconds)
          update_location("suspend_time_on_unacceptable", seconds.nil?)
          seconds ||= Milter::Client::DEFAULT_SUSPEND_TIME_ON_UNACCEPTABLE
          @configuration.suspend_time_on_unacceptable = seconds
        end

        def suspend_time_on_unacceptable
          @configuration.suspend_time_on_unacceptable
        end

        def max_connections=(n_connections)
          update_location("max_connections", n_connections.nil?)
          n_connections ||= Milter::Client::DEFAULT_MAX_CONNECTIONS
          @configuration.max_connections = n_connections
        end

        def max_connections
          @configuration.max_connections
        end

        def max_file_descriptors=(n_descriptors)
          update_location("max_file_descriptors", n_descriptors.nil?)
          n_descriptors ||= 0
          @configuration.max_file_descriptors = n_descriptors
        end

        def max_file_descriptors
          @configuration.max_file_descriptors
        end

        def connection_check_interval=(interval)
          update_location("connection_check_interval", interval.nil?)
          interval ||= 0
          @configuration.connection_check_interval = interval
        end

        def event_loop_backend
          @configuration.event_loop_backend
        end

        def event_loop_backend=(backend)
          update_location("event_loop_backend", backend.nil?)
          @configuration.event_loop_backend = backend
        end

        def n_workers
          @configuration.n_workers
        end

        def n_workers=(n_workers)
          update_location("n_workers", n_workers.nil?)
          n_workers ||= 0
          @configuration.n_workers = n_workers
        end

        def packet_buffer_size
          @configuration.packet_buffer_size
        end

        def packet_buffer_size=(size)
          update_location("size", size.nil?)
          size ||= 0
          @configuration.packet_buffer_size = size
        end

        def use_syslog?
          @configuration.use_syslog?
        end

        def use_syslog=(boolean)
          update_location("use_syslog", !boolean)
          @configuration.use_syslog = boolean
        end

        def syslog_facility
          @configuration.syslog_facility
        end

        def syslog_facility=(facility)
          update_location("syslog_facility", facility == "mail")
          @configuration.syslog_facility = facility
        end

        def maintained(hook=Proc.new)
          guarded_hook = Proc.new do |configuration|
            ConfigurationLoader.guard do
              hook.call
            end
          end
          @configuration.maintained_hooks << guarded_hook
        end

        private
        def update_location(key, reset, deep_level=2)
          full_key = "milter.#{key}"
          @configuration.update_location(full_key, reset, deep_level)
        end
      end

      class DatabaseConfigurationLoader
        def initialize(configuration)
          @configuration = configuration
        end

        def type
          @configuration.type
        end

        def type=(type)
          update_location("type", type.nil?)
          @configuration.type = type
        end

        def name
          @configuration.name
        end

        def name=(name)
          update_location("name", name.nil?)
          @configuration.name = name
        end

        def host
          @configuration.host
        end

        def host=(host)
          update_location("host", host.nil?)
          @configuration.host = host
        end

        def port
          @configuration.port
        end

        def port=(port)
          update_location("port", port.nil?)
          @configuration.port = port
        end

        def path
          @configuration.path
        end

        def path=(path)
          update_location("path", path.nil?)
          @configuration.path = path
        end

        def user
          @configuration.user
        end

        def user=(user)
          update_location("user", user.nil?)
          @configuration.user = user
        end

        def password
          @configuration.password
        end

        def password=(password)
          update_location("password", password.nil?)
          @configuration.password = password
        end

        def setup
          if @configuration.type.nil?
            raise MissingValue.new("database.type")
          end
          @configuration.setup("database.")
        end

        def load_models(path)
          resolved_paths = @configuration.resolve_path(path)
          resolved_paths.each do |resolved_path|
            begin
              require(resolved_path)
              @configuration.add_loaded_model_file(resolved_path)
            rescue Exception => error
              Milter::Logger.error(error)
            end
          end
        end

        private
        def update_location(key, reset, deep_level=2)
          full_key = "database.#{key}"
          @configuration.update_location(full_key, reset, deep_level)
        end
      end
    end
  end
end