require "tty-spinner"
require "tty-progressbar"

module Astrolabe
  class SyncService
    BATCH_SIZE = GithubClient::RELEASE_BATCH_SIZE
    MAX_THREADS = 10

    def initialize(db:, client: GithubClient.new)
      @db = db
      @client = client
      @pastel = Pastel.new
    end

    def sync
      stars = fetch_stars
      return stars if stars.failure?

      repos = stars.data

      results = check_releases(repos)
      return results if results.failure?

      data = results.data
      @db.log_sync(
        repos_checked: data[:repos_synced],
        new_releases_found: data[:new_releases].size
      )

      data[:rate_limit] = @client.last_rate_limit
      Result.success(data)
    end

    private

    def fetch_stars
      spinner = TTY::Spinner.new(
        "#{@pastel.cyan(":spinner")} Fetching starred repos...",
        format: :dots
      )
      spinner.auto_spin

      repos = @client.fetch_starred_repos
      spinner.success(@pastel.green("(#{repos.size} repos)"))

      Result.success(repos)
    rescue RateLimitError => e
      spinner.error(@pastel.red("(rate limited)"))
      Result.failure("Rate limited while fetching stars: #{e.message}")
    rescue GhCliError => e
      spinner.error(@pastel.red("(failed)"))
      Result.failure(e.message)
    end

    def check_releases(repos)
      new_releases = []
      first_sync_repos = []
      repos_synced = 0
      rate_limited = false
      errors = []

      bar = TTY::ProgressBar.new(
        "#{@pastel.cyan("Checking releases")} [:bar] :current/:total :percent ETA :eta",
        total: repos.size,
        width: 30,
        bar_format: :block
      )

      repo_ids = {}
      repos.each do |repo_data|
        repo_ids[repo_data[:full_name]] = @db.upsert_repo(repo_data)
      end

      # Build batches and fetch all in parallel
      batches = repos.each_slice(BATCH_SIZE).to_a
      batch_results = fetch_batches_parallel(batches, bar)

      # Process results sequentially (DB writes + progress bar)
      batches.zip(batch_results).each do |batch, fetch_result|
        if fetch_result.is_a?(RateLimitError)
          rate_limited = true
          bar.log(@pastel.red("Rate limited — stopping early"))
          break
        elsif fetch_result.is_a?(GhCliError)
          errors << fetch_result.message
          bar.log(@pastel.yellow("Batch error: #{fetch_result.message[0..80]}"))
          batch.size.times { bar.advance }
          repos_synced += batch.size
          next
        end

        releases = fetch_result

        batch.each do |repo_data|
          name = repo_data[:full_name]
          release = releases[name]
          repo = @db.find_repo(name)
          repo_id = repo_ids[name]

          if release.nil?
            repos_synced += 1
            bar.advance
            next
          end

          if repo["last_known_tag"].nil?
            @db.update_repo_checked(repo_id, release[:tag_name])
            @db.insert_release(repo_id, release.merge(old_tag: nil))
            first_sync_repos << name
          elsif repo["last_known_tag"] != release[:tag_name]
            old_tag = repo["last_known_tag"]
            @db.insert_release(repo_id, release.merge(old_tag: old_tag))
            @db.update_repo_checked(repo_id, release[:tag_name])
            new_releases << {
              full_name: name,
              old_tag: old_tag,
              new_tag: release[:tag_name],
              name: release[:name],
              body: release[:body],
              published_at: release[:published_at]
            }
          end

          repos_synced += 1
          bar.advance
        end
      end

      bar.finish unless rate_limited

      Result.success({
        repos_synced: repos_synced,
        new_releases: new_releases,
        first_sync: first_sync_repos,
        rate_limited: rate_limited,
        errors: errors
      })
    end

    # Fetches all batches using a thread pool.
    # Returns an array of results (Hash or Exception) in batch order.
    def fetch_batches_parallel(batches, bar)
      results = Array.new(batches.size)
      mutex = Mutex.new
      index = -1

      threads = [MAX_THREADS, batches.size].min.times.map do
        Thread.new do
          loop do
            i = mutex.synchronize { index += 1 }
            break if i >= batches.size

            begin
              batch_names = batches[i].map { |r| r[:full_name] }
              results[i] = @client.fetch_releases_batch(batch_names)
              mutex.synchronize { bar.advance(batches[i].size) }
            rescue RateLimitError => e
              results[i] = e
              break
            rescue GhCliError => e
              results[i] = e
              mutex.synchronize { bar.advance(batches[i].size) }
            end
          end
        end
      end

      threads.each(&:join)

      # Reset bar for the sequential processing pass
      bar.reset
      results
    end
  end
end
