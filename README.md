# actions

Shared GitHub Actions for Eleanor Health repositories, one directory per action.

| Action | Purpose |
|---|---|
| [`update-go`](update-go) | Bump Go dependencies and the Go version, open a PR |

`lib/` holds scripts shared by several actions (they are called through `${{ github.action_path }}/../lib`).

## Using an action

Pin the floating major tag so fixes arrive without a PR to every repo:

```yaml
- uses: eleanorhealth/actions/update-go@update-go/v1
```

This repo must allow access from other repositories: Settings, Actions, General, Access,
"Accessible from repositories in the eleanorhealth organization".

## Versioning

Each action is versioned on its own with tags named `<action>/vX.Y.Z`, for example `update-go/v1.2.3`.

- Release: `git tag update-go/v1.2.3 && git push origin update-go/v1.2.3`.
- The [release workflow](.github/workflows/release.yml) then moves `update-go/v1` to that commit.
- A change under `lib/` only reaches callers once each action that uses it is re-tagged.
- Breaking changes get a new major (`v2`), callers opt in by changing the ref.

## update-go

Runs `go get <module>@latest` for every direct dependency, bumps the Go version to the latest stable
release (minor or patch) in `go.mod`, `Dockerfile` (`FROM golang:`) and `.tool-versions` when they exist,
runs `go mod tidy`, and opens or refreshes one PR on `chore/update-dependencies-go`.

Caller example (the schedule trigger has to live in each repository):

```yaml
name: Update Go dependencies

on:
  schedule:
    - cron: "0 12 * * 1" # Monday 12:00 UTC
  workflow_dispatch:

concurrency:
  group: update-dependencies-go
  cancel-in-progress: false

jobs:
  update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    env:
      GOPRIVATE: github.com/eleanorhealth/* # only if you have private modules
    steps:
      - uses: actions/checkout@v6.0.2
        with:
          fetch-depth: 0 # create-pr diffs against origin/main

      - uses: actions/setup-go@v6.3.0
        with:
          go-version-file: go.mod

      # only if you have private modules
      - run: git config --global url."https://x-access-token:${{ secrets.GH_TOKEN }}@github.com/eleanorhealth".insteadOf "https://github.com/eleanorhealth"

      - uses: eleanorhealth/actions/update-go@update-go/v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          pinned-deps: github.com/unidoc/unipdf/v3 # optional
```

| Input | Default | |
|---|---|---|
| `github-token` | required | pushes the branch, opens the PR |
| `pinned-deps` | none | whitespace separated modules to leave alone |
| `pr-branch` | `chore/update-dependencies-go` | |
| `pr-labels` | `dependencies,go` | |
| `base-branch` | `main` | |

Outputs: `updated` (`true` if a PR was created or refreshed) and `pr-url`.
