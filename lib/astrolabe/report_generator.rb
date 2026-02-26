require "tty-markdown"
require "date"
require "time"

module Astrolabe
  class ReportGenerator
    def initialize(db:)
      @db = db
      @pastel = Pastel.new
      @today = Date.today
    end

    STALE_THRESHOLD_DAYS = 3

    def generate(days: 7, full: false)
      sync = @db.latest_sync
      return Result.failure("No sync data found. Run 'astrolabe --sync' first.") unless sync

      sync_age = (Time.now - Time.parse(sync["synced_at"])) / 86400
      @stale_warning = if sync_age >= STALE_THRESHOLD_DAYS
        @pastel.yellow("Data is #{sync_age.floor} days old. Run 'astrolabe --sync' to refresh.")
      end

      since = (Time.now - (days * 86400)).strftime("%Y-%m-%d %H:%M:%S")
      releases = @db.releases_since(since)

      period = "#{days} #{days == 1 ? "day" : "days"}"

      if releases.empty?
        lines = [@pastel.yellow("No new releases in the last #{period}.")]
        lines << @pastel.dim("Last sync: #{sync["synced_at"]} (#{sync["repos_checked"]} repos)")
        lines << @stale_warning if @stale_warning
        return Result.success(lines.join("\n"))
      end

      repo_count = releases.map { |r| r["full_name"] }.uniq.size
      repo_width = releases.map { |r| r["full_name"].length }.max

      output = []
      output << @stale_warning if @stale_warning
      output << @pastel.bold("#{releases.size} releases across #{repo_count} repos in the last #{period}")
      output << @pastel.dim("Last sync: #{sync["synced_at"]}")
      output << ""

      by_day = releases
        .group_by { |r| r["published_at"]&.split("T")&.first || "unknown" }
        .sort_by { |date, _| date }
        .reverse

      by_day.each do |date_str, day_releases|
        output << @pastel.bold(relative_date(date_str))
        output << @pastel.dim("─" * 50)

        day_releases
          .sort_by { |r| r["full_name"].downcase }
          .each do |rel|
            output << release_line(rel, repo_width)
            output << render_body(rel) if full
          end

        output << ""
      end

      Result.success(output.join("\n"))
    end

    private

    def release_line(rel, repo_width)
      name = rel["full_name"]
      version = format_version(rel)
      repo_url = "https://github.com/#{name}"
      release_url = "https://github.com/#{name}/releases/tag/#{rel["tag_name"]}"

      padding = " " * (repo_width - name.length)
      linked_name = terminal_link(repo_url, @pastel.cyan(name))
      linked_version = terminal_link(release_url, @pastel.green(version))

      line = "  #{padding}#{linked_name} #{@pastel.dim("│")} #{linked_version}"

      desc = (rel["repo_description"] || "").strip
      unless desc.empty?
        max_width = 75
        desc_padding = " " * (repo_width + 5)
        words = desc.split
        lines = []
        current = ""
        words.each do |word|
          if current.empty?
            current = word
          elsif (current.length + 1 + word.length) <= max_width
            current += " #{word}"
          else
            lines << current
            current = word
            break if lines.size >= 2
          end
        end
        lines << current if lines.size < 2 && !current.empty?
        lines[-1] += "..." if lines.size >= 2 && lines.join(" ").length < desc.length
        line += lines.map { |l| "\n#{desc_padding}#{@pastel.dim(l)}" }.join
      end

      line
    end

    def format_version(rel)
      if rel["old_tag"]
        "#{rel["old_tag"]} → #{rel["tag_name"]}"
      else
        rel["tag_name"]
      end
    end

    def render_body(rel)
      body = (rel["body"] || "").strip
      if body.empty?
        @pastel.dim("  (no release notes)")
      else
        TTY::Markdown.parse(body, width: 90, indent: 2)
      end
    end

    def terminal_link(url, text)
      "\e]8;;#{url}\a#{text}\e]8;;\a"
    end

    def relative_date(date_str)
      return date_str unless date_str.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      date = Date.parse(date_str)
      diff = (@today - date).to_i
      formatted = date.strftime("%b %-d, %Y")

      case diff
      when 0 then "Today (#{formatted})"
      when 1 then "Yesterday (#{formatted})"
      else "#{diff} days ago (#{formatted})"
      end
    end
  end
end
