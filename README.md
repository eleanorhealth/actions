# actions

Shared GitHub Actions for Eleanor Health repositories, one directory per action.

| Action | Purpose |
|---|---|
| [`update-go`](update-go) | Bump Go dependencies and the Go version, open a PR |
| [`update-js`](update-js) | Bump JS dependencies with npm-check-updates, open a PR |

`lib/` holds scripts shared by several actions (they are called through `${{ github.action_path }}/../lib`).
`lib/create-pr` commits the files an action changed, pushes a branch and opens or refreshes the PR; it is
configured through env vars (see the header of the script), each action sets them.

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
| `pr-title` | `chore(deps): weekly Go dependency update` | |
| `pr-labels` | `dependencies,go` | |
| `base-branch` | `main` | |

Empty strings fall back to the defaults, so `workflow_dispatch` inputs can be forwarded as they are.
Outputs: `updated` (`true` if a PR was created or refreshed) and `pr-url`.

## update-js

Runs [npm-check-updates](https://github.com/raineorshine/npm-check-updates) on the direct dependencies
(major bumps included), then `yarn install` to refresh `yarn.lock`, and opens or refreshes one PR on
`chore/update-dependencies-js`. The PR commits `package.json`, `packages/*/package.json` and `yarn.lock`.

The action does not install anything: the caller sets up node, yarn and the registry auth (for private
`@eleanorhealth` packages) before it, for example with the repo's `bin/setup`.

After npm-check-updates runs, exact pins in the root `resolutions` (for example `"react": "19.3.0"`) are moved to the version of the matching direct dependency. Without that, yarn installs two copies of the package. Ranges are left alone.

Packages that stay on a major or minor, or are skipped, go in the repo's `.ncurc.js`, which
npm-check-updates reads from the working directory:

```js
const KEPT_MAJOR = {
  "@types/node": "minor", // match the node version in Dockerfile
  jsdom: "minor", // 28+ breaks the modal tests
};

module.exports = {
  target: (name) => KEPT_MAJOR[name] ?? "latest",
  reject: ["@eleanorhealth/*"], // skipped entirely
};
```

Caller example:

```yaml
name: Update JS dependencies

on:
  schedule:
    - cron: "0 16 * * 2" # Tuesday 16:00 UTC
  workflow_dispatch:
    inputs:
      packages:
        description: "Comma-separated npm-check-updates --filter globs. Leave empty to update everything."
        required: false
        default: ""
      pr_branch:
        description: "Branch name for this update. Leave empty for the default."
        required: false
        default: ""
      pr_title:
        description: "PR title. Leave empty for the default."
        required: false
        default: ""
      base_branch:
        description: "PR base branch"
        required: false
        default: "main"

concurrency:
  group: update-dependencies-js
  cancel-in-progress: false

jobs:
  update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v6.0.2
        with:
          fetch-depth: 0 # create-pr diffs against the base branch

      - name: Setup toolchain and install dependencies
        env:
          GITHUB_TOKEN: ${{ secrets.GH_TOKEN }}
        run: ./bin/setup

      - uses: eleanorhealth/actions/update-js@update-js/v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          packages: ${{ inputs.packages }}
          workspaces: "true" # yarn workspaces repos only
          pr-branch: ${{ inputs.pr_branch }}
          pr-title: ${{ inputs.pr_title }}
          base-branch: ${{ inputs.base_branch }}
```

| Input | Default | |
|---|---|---|
| `github-token` | required | pushes the branch, opens the PR |
| `packages` | all | comma separated `--filter` globs, for scoped update PRs |
| `workspaces` | `false` | `true` also updates the root and every workspace `package.json` |
| `pr-branch` | `chore/update-dependencies-js` | |
| `pr-title` | `chore(deps): weekly JS dependency update` | |
| `pr-labels` | `dependencies,javascript` | |
| `base-branch` | `main` | |

Outputs: `updated` and `pr-url`, as for `update-go`.
