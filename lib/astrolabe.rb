require "fileutils"
require "pastel"

module Astrolabe
  VERSION = "0.1.0"

  def self.db_path
    data_dir = ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share"))
    File.join(data_dir, "astrolabe", "astrolabe.db")
  end
end

require_relative "astrolabe/result"
require_relative "astrolabe/database"
require_relative "astrolabe/github_client"
require_relative "astrolabe/sync_service"
require_relative "astrolabe/report_generator"
require_relative "astrolabe/commands/list"
require_relative "astrolabe/commands/reset"
require_relative "astrolabe/cli"
