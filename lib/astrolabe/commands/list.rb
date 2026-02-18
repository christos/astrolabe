module Astrolabe
  module Commands
    class List
      def self.option_parser(opts)
        opts[:language] = nil
        parser = OptionParser.new do |o|
          o.banner = "Usage: astrolabe list [options]"
          o.on("--language LANG", "Filter by language") { |l| opts[:language] = l }
          o.on("-h", "--help", "Show help") { puts o; exit }
        end
        parser
      end

      def initialize(_global_options, command_options, _args)
        @language = command_options[:language]
      end

      def execute
        pastel = Pastel.new
        db = Database.new
        repos = db.all_repos(language: @language)

        if repos.empty?
          $stderr.puts pastel.yellow("No tracked repos. Run 'astrolabe --sync' first.")
          exit 1
        end

        repos.each do |repo|
          tag = repo["last_known_tag"]
          lang = repo["language"]

          line = pastel.cyan(repo["full_name"])
          line += "  #{pastel.green(tag)}" if tag
          line += "  #{pastel.dim(lang)}" if lang
          puts line
        end

        puts ""
        puts pastel.dim("#{repos.size} repos tracked")
      end
    end
  end
end
