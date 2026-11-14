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

## Cooldown

Both actions skip versions that were published less than a cooldown ago (`cooldown` input, default `7d`,
also `12h`, `30m`, or `0` to turn it off). Most compromised releases are caught within days, so waiting
keeps a hijacked release out of the weekly PR.

| What | How the age is read | When held back |
|---|---|---|
| npm packages | `npm-check-updates --cooldown` | the newest version past the cooldown is used, silently |
| Go modules | publish time from the Go module proxy | the newest release past the cooldown is used, or the module stays as it is, with a line in the log |
| Go version (`go.mod`, `golang:` tags) | publish time of the toolchain on the Go module proxy | a **warning annotation** on the run, the previous version stays |
| Node version | release date from nodejs.org, taken as 00:00 UTC that day | a **warning annotation** on the run, the newest older LTS is used |

Language versions warn because a held-back Go or Node release can be a security fix that is waiting
to be adopted. A Go release the proxy does not know yet counts as inside the cooldown. Module and
package versions are only logged, since there is always another one coming.

`update-js` runs a pinned `npm-check-updates` (`NCU_VERSION` in `update-js/bin/update-deps`), so a hijacked
release of the tool itself does not run with the job's token. Bump the pin by hand, to a release that is
past the cooldown.

## update-go

Runs `go get` for every direct dependency, bumps the Go version to the latest stable
release (minor or patch) past the [cooldown](#cooldown) in `go.mod`, `Dockerfile` (`FROM golang:`) and `.tool-versions` when they exist,
keeps `golang:<version>` image tags in `cicd/*.yaml` in step with the `go` directive (on every run, not only when
a new release is out), runs `go mod tidy`, and opens or refreshes one PR on `chore/update-dependencies-go`.

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
| `working-directory` | `.` | directory with `go.mod`, `Dockerfile` and `.tool-versions`, for monorepos with one module per directory. Each directory's own `.tool-versions` is updated |
| `cooldown` | `7d` | minimum age of a Go release or module version to adopt, `0` disables, see [Cooldown](#cooldown) |
| `image-files` | `cicd/*.yaml cicd/*.yml` | globs, relative to `working-directory`, whose `golang:<version>` image tags (for example Cloud Build steps) follow the `go` directive. The tag suffix, such as `-alpine`, is kept |
| `workspace-directory` | none | directory with `go.work` and a shared `.tool-versions`. Their Go version is raised (never lowered) along with the module's, and they are committed in the same PR |

Empty strings fall back to the defaults, so `workflow_dispatch` inputs can be forwarded as they are.
Outputs: `updated` (`true` if a PR was created or refreshed) and `pr-url`.

## update-js

Runs [npm-check-updates](https://github.com/raineorshine/npm-check-updates) on the direct dependencies
(major bumps included, versions younger than the cooldown skipped), moves Node to the latest LTS, then refreshes the lockfile, and opens or refreshes one PR on
`chore/update-dependencies-js`. A repo with a `pnpm-lock.yaml` gets `pnpm install`; any other gets
`yarn install`. The PR commits `package.json`, `packages/*/package.json` and the lockfile.

Node is moved to the latest LTS release (even majors only, never a "Current" line) in `Dockerfile`
(`FROM node:`), `.nvmrc` and `.tool-versions`. Versions only go up, the precision is kept (`node:24` stays a
major tag) and tag suffixes such as `-alpine` are preserved. Other images (postgres, redis, ...) are left alone.

Versions published less than the [cooldown](#cooldown) ago (default 7 days) are not adopted, Node releases
included.

The action does not install anything: the caller sets up node, the package manager and the registry
auth (for private `@eleanorhealth` packages) before it, for example with the repo's `bin/setup`, or
`corepack enable` for a pnpm repo that pins `packageManager`.

After npm-check-updates runs, exact pins in the root `resolutions` (for example `"react": "19.3.0"`) are moved to the version of the matching direct dependency. Without that, yarn installs two copies of the package. Ranges are left alone. pnpm's `pnpm.overrides`
are not synced.

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
          workspaces: "true" # yarn or pnpm workspaces repos only
          pr-branch: ${{ inputs.pr_branch }}
          pr-title: ${{ inputs.pr_title }}
          base-branch: ${{ inputs.base_branch }}
```

| Input | Default | |
|---|---|---|
| `github-token` | required | pushes the branch, opens the PR |
| `packages` | all | comma separated `--filter` globs, for scoped update PRs |
| `cooldown` | `7d` | minimum age of a package version or Node release to adopt, `0` disables, see [Cooldown](#cooldown) |
| `node-files` | `Dockerfile .nvmrc .tool-versions` | globs whose Node version follows the latest LTS |
| `workspaces` | `false` | `true` also updates the root and every workspace `package.json` |
| `pr-branch` | `chore/update-dependencies-js` | |
| `pr-title` | `chore(deps): weekly JS dependency update` | |
| `pr-labels` | `dependencies,javascript` | |
| `base-branch` | `main` | |

Outputs: `updated` and `pr-url`, as for `update-go`.
