# Astrolabe

Track GitHub releases for your starred repos.

Astrolabe syncs your GitHub stars and checks for new releases, giving you a
concise report of what shipped recently. Think of it as a personal release feed
powered by the repos you already star.

## Requirements

- Ruby >= 3.1
- [GitHub CLI](https://cli.github.com/) (`gh`) — authenticated

## Install

```sh
gem install specific_install
gem specific_install -l https://github.com/christos/astrolabe.git
```

## Usage

```sh
# First run — sync your starred repos and show releases from the last week
astrolabe --sync

# Show releases without syncing (uses cached data)
astrolabe

# Show releases from the last 3 days
astrolabe --days 3

# Include full release notes (rendered markdown)
astrolabe --sync --full

# List all tracked repos
astrolabe list

# Filter tracked repos by language
astrolabe list --language ruby

# Clear the database and start fresh
astrolabe reset
```

## How it works

1. Fetches your starred repos via the GitHub REST API (paginated, parallel)
2. Checks each repo for its latest release via a batched GraphQL query
3. Stores everything in a local SQLite database at `~/.local/share/astrolabe/astrolabe.db`
4. On subsequent syncs, detects new releases by comparing against the last known tag

The first sync baselines all repos — only releases that appear after that are
reported as new.

## License

MIT
