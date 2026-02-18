require "tty-prompt"

module Astrolabe
  module Commands
    class Reset
      def self.option_parser(opts)
        opts[:force] = false
        parser = OptionParser.new do |o|
          o.banner = "Usage: astrolabe reset [options]"
          o.on("--force", "Skip confirmation") { opts[:force] = true }
          o.on("-h", "--help", "Show help") { puts o; exit }
        end
        parser
      end

      def initialize(_global_options, command_options, _args)
        @force = command_options[:force]
      end

      def execute
        pastel = Pastel.new
        db = Database.new

        count = db.repo_count
        if count == 0
          puts pastel.dim("Database is already empty.")
          return
        end

        unless @force
          prompt = TTY::Prompt.new
          confirmed = prompt.yes?(
            "This will delete all data (#{count} tracked repos). Continue?",
            default: false
          )
          unless confirmed
            puts pastel.dim("Cancelled.")
            return
          end
        end

        db.reset!
        puts pastel.green("Database cleared.")
      end
    end
  end
end
