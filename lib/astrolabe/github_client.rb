require "open3"
require "json"

module Astrolabe
  class GhCliError < StandardError; end
  class RateLimitError < GhCliError; end
  class GhNotFoundError < GhCliError; end

  class GithubClient
    STARS_PER_PAGE = 100
    RELEASE_BATCH_SIZE = 100

    attr_reader :last_rate_limit

    JQ_STARS = '.[] | {full_name: .full_name, description: .description, language: .language}'

    # Fetches starred repos with parallel REST pagination.
    # Page 1 fetched with headers to discover total pages,
    # then all remaining pages fetched concurrently via threads.
    def fetch_starred_repos
      first_page, last_page = fetch_first_star_page
      return first_page if last_page <= 1

      remaining = fetch_remaining_star_pages(last_page)
      first_page.concat(remaining)
    end

    # Fetches latest release info for up to RELEASE_BATCH_SIZE repos
    # in a single GraphQL query (cost: 1 point regardless of count).
    def fetch_releases_batch(repo_names)
      return {} if repo_names.empty?

      query = build_releases_query(repo_names)
      stdout, stderr, status = Open3.capture3("gh", "api", "graphql", "-f", "query=#{query}")

      unless status.success?
        raise RateLimitError, stderr if rate_limit_error?(stderr)
        raise GhCliError, "GraphQL query failed: #{stderr.strip}"
      end

      parse_graphql_releases(stdout, repo_names)
    end

    private

    # --- Stars (REST parallel) ---

    def fetch_first_star_page
      stdout, stderr, status = Open3.capture3(
        "gh", "api", "/user/starred?per_page=#{STARS_PER_PAGE}&page=1", "-i"
      )
      raise_gh_error(stderr) unless status.success?

      header_section, body = stdout.split(/\r?\n\r?\n/, 2)
      last_page = parse_last_page(header_section)
      repos = JSON.parse(body).map { |r| extract_repo(r) }

      [repos, last_page]
    end

    def fetch_remaining_star_pages(last_page)
      threads = (2..last_page).map do |page|
        Thread.new(page) do |p|
          out, err, st = Open3.capture3(
            "gh", "api", "/user/starred?per_page=#{STARS_PER_PAGE}&page=#{p}",
            "--jq", JQ_STARS
          )
          raise_gh_error(err) unless st.success?
          parse_ndjson(out)
        end
      end

      error = nil
      results = []
      threads.each do |t|
        begin
          results.concat(t.value)
        rescue => e
          error ||= e
        end
      end

      raise error if error
      results
    end

    def parse_last_page(headers)
      match = headers.match(/page=(\d+)>;\s*rel="last"/)
      match ? match[1].to_i : 1
    end

    def extract_repo(raw)
      {
        full_name: raw["full_name"],
        description: raw["description"],
        language: raw["language"]
      }
    end

    def parse_ndjson(output)
      output.each_line.filter_map do |line|
        line = line.strip
        next if line.empty?
        parsed = JSON.parse(line)
        {
          full_name: parsed["full_name"],
          description: parsed["description"],
          language: parsed["language"]
        }
      end
    end

    # --- Releases (GraphQL batched) ---

    def build_releases_query(repo_names)
      fragments = repo_names.each_with_index.map do |full_name, i|
        owner, name = full_name.split("/", 2)
        owner = owner.gsub('"', '\\"')
        name = name.gsub('"', '\\"')
        <<~GQL.chomp
          repo#{i}: repository(owner: "#{owner}", name: "#{name}") {
            nameWithOwner
            latestRelease {
              tagName
              name
              description
              publishedAt
            }
          }
        GQL
      end

      "{ rateLimit { remaining limit used } #{fragments.join("\n")} }"
    end

    def parse_graphql_releases(stdout, repo_names)
      parsed = JSON.parse(stdout)
      data = parsed["data"] || {}

      if data["rateLimit"]
        @last_rate_limit = data["rateLimit"]
      end

      results = {}

      repo_names.each_with_index do |full_name, i|
        repo_data = data["repo#{i}"]
        next unless repo_data

        release = repo_data["latestRelease"]
        next unless release

        results[full_name] = {
          tag_name: release["tagName"],
          name: release["name"],
          body: release["description"],
          published_at: release["publishedAt"]
        }
      end

      results
    end

    # --- Shared ---

    def raise_gh_error(stderr)
      raise RateLimitError, stderr if rate_limit_error?(stderr)
      raise GhCliError, "gh api failed: #{stderr.strip}"
    end

    def rate_limit_error?(stderr)
      stderr.include?("rate limit") || stderr.include?("secondary rate")
    end
  end
end
