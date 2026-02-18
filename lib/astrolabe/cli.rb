require "optparse"

module Astrolabe
  class CLI
    COMMANDS = {
      "list"  => Commands::List,
      "reset" => Commands::Reset
    }.freeze

    def self.run(argv)
      new.run(argv)
    end

    def run(argv)
      options = {}
      parser = build_parser(options)

      begin
        parser.order!(argv)
      rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
        $stderr.puts e.message
        $stderr.puts parser
        exit 1
      end

      command_name = argv.shift

      if command_name && COMMANDS[command_name]
        command_options = {}
        command_parser = COMMANDS[command_name].option_parser(command_options)
        begin
          command_parser.parse!(argv)
        rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
          $stderr.puts e.message
          $stderr.puts command_parser
          exit 1
        end
        COMMANDS[command_name].new(options, command_options, argv).execute
      elsif command_name
        $stderr.puts "Unknown command: #{command_name}"
        $stderr.puts "Available commands: #{COMMANDS.keys.join(", ")}"
        exit 1
      else
        run_default(options)
      end
    rescue Errno::ENOENT => e
      if e.message.include?("gh")
        $stderr.puts "Error: GitHub CLI (gh) not found."
        $stderr.puts "Install it: https://cli.github.com/"
        exit 1
      end
      raise
    rescue GhCliError => e
      $stderr.puts "GitHub API error: #{e.message}"
      exit 1
    rescue SQLite3::Exception => e
      $stderr.puts "Database error: #{e.message}"
      exit 1
    end

    private

    def run_default(options)
      pastel = Pastel.new
      db = Database.new

      if options[:sync]
        service = SyncService.new(db: db)
        result = service.sync

        if result.failure?
          $stderr.puts pastel.red("Sync failed: #{result.error}")
          exit 1
        end

        data = result.data
        puts ""

        if data[:first_sync].any?
          puts pastel.yellow("Baselined #{data[:first_sync].size} repos (first sync — not counted as new)")
        end

        summary = "Checked #{data[:repos_synced]} repos."
        if data[:rate_limit]
          remaining = data[:rate_limit]["remaining"]
          limit = data[:rate_limit]["limit"]
          summary += " API: #{remaining}/#{limit} remaining."
        end
        puts pastel.dim(summary)

        if data[:rate_limited]
          puts pastel.yellow("Sync stopped early due to rate limiting. Run again later.")
        end

        puts ""
      end

      generator = ReportGenerator.new(db: db)
      result = generator.generate(days: options[:days], full: options[:full])

      if result.failure?
        $stderr.puts pastel.yellow(result.error)
        exit 1
      end

      puts result.data
    end

    def build_parser(opts)
      opts[:sync] = false
      opts[:days] = 7
      opts[:full] = false

      OptionParser.new do |o|
        o.banner = "Usage: astrolabe [options] [command]"
        o.separator ""
        o.separator "Options:"
        o.on("--sync", "Sync starred repos and check releases") { opts[:sync] = true }
        o.on("--days N", Integer, "Show releases from last N days (default: 7)") { |n| opts[:days] = n }
        o.on("--full", "Include full release notes") { opts[:full] = true }
        o.on("-v", "--version", "Show version") { puts "astrolabe #{VERSION}"; exit }
        o.on("-h", "--help", "Show help") { puts o; exit }
        o.separator ""
        o.separator "Commands:"
        o.separator "  list     List all tracked repos"
        o.separator "  reset    Clear the database"
        o.separator ""
        o.separator "With no command, shows the release report."
        o.separator "Use --sync to fetch latest data first."
      end
    end
  end
end
