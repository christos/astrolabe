require "sqlite3"

module Astrolabe
  class Database
    def initialize(path = Astrolabe.db_path)
      FileUtils.mkdir_p(File.dirname(path))
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = true
      @db.execute("PRAGMA journal_mode=WAL")
      @db.execute("PRAGMA foreign_keys=ON")
      migrate!
    end

    def upsert_repo(data)
      @db.execute(<<~SQL, [data[:full_name], data[:description], data[:language]])
        INSERT INTO repos (full_name, description, language)
        VALUES (?, ?, ?)
        ON CONFLICT(full_name) DO UPDATE SET
          description = excluded.description,
          language = excluded.language
      SQL
      @db.execute("SELECT id FROM repos WHERE full_name = ?", [data[:full_name]]).first["id"]
    end

    def find_repo(full_name)
      @db.execute("SELECT * FROM repos WHERE full_name = ?", [full_name]).first
    end

    def all_repos(language: nil)
      if language
        @db.execute(
          "SELECT * FROM repos WHERE lower(language) = lower(?) ORDER BY full_name",
          [language]
        )
      else
        @db.execute("SELECT * FROM repos ORDER BY full_name")
      end
    end

    def repo_count
      @db.execute("SELECT COUNT(*) AS count FROM repos").first["count"]
    end

    def update_repo_checked(repo_id, tag_name)
      @db.execute(
        "UPDATE repos SET last_checked_at = datetime('now'), last_known_tag = ? WHERE id = ?",
        [tag_name, repo_id]
      )
    end

    def insert_release(repo_id, release_data)
      params = [
        repo_id,
        release_data[:tag_name],
        release_data[:name],
        release_data[:body],
        release_data[:published_at],
        release_data[:old_tag]
      ]
      @db.execute(<<~SQL, params)
        INSERT OR IGNORE INTO releases (repo_id, tag_name, name, body, published_at, old_tag)
        VALUES (?, ?, ?, ?, ?, ?)
      SQL
    end

    def releases_since(timestamp)
      @db.execute(<<~SQL, [timestamp])
        SELECT r.*, repos.full_name, repos.language, repos.description AS repo_description
        FROM releases r
        JOIN repos ON repos.id = r.repo_id
        WHERE r.published_at >= ?
        ORDER BY r.published_at DESC
      SQL
    end

    def latest_sync
      @db.execute("SELECT * FROM sync_log ORDER BY id DESC LIMIT 1").first
    end

    def log_sync(repos_checked:, new_releases_found:)
      @db.execute(
        "INSERT INTO sync_log (repos_checked, new_releases_found) VALUES (?, ?)",
        [repos_checked, new_releases_found]
      )
    end

    def reset!
      @db.execute("DROP TABLE IF EXISTS releases")
      @db.execute("DROP TABLE IF EXISTS sync_log")
      @db.execute("DROP TABLE IF EXISTS repos")
      migrate!
    end

    private

    def migrate!
      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS repos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          full_name TEXT UNIQUE NOT NULL,
          description TEXT,
          language TEXT,
          last_checked_at TEXT,
          last_known_tag TEXT
        )
      SQL

      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS releases (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          repo_id INTEGER NOT NULL,
          tag_name TEXT NOT NULL,
          name TEXT,
          body TEXT,
          published_at TEXT,
          old_tag TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (repo_id) REFERENCES repos(id) ON DELETE CASCADE
        )
      SQL

      @db.execute(<<~SQL)
        CREATE UNIQUE INDEX IF NOT EXISTS idx_releases_repo_tag
          ON releases(repo_id, tag_name)
      SQL

      @db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS sync_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          synced_at TEXT NOT NULL DEFAULT (datetime('now')),
          repos_checked INTEGER NOT NULL DEFAULT 0,
          new_releases_found INTEGER NOT NULL DEFAULT 0
        )
      SQL
    end
  end
end
