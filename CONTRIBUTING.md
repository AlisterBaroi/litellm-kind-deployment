# Contributing

Thanks for wanting to help. This repo is a deployment guide, and its whole subject is upstream churn: charts change, images move, releases break things. That shapes what a useful contribution looks like here.

## What helps most

1. Breakage reports. If a step stopped working, open an issue with the step, the exact error output, your versions (`kind version`, `helm version`, `docker version`, the chart version, and `LITELLM_VERSION`), and your OS. A good report is as valuable as a fix, because finding out that something broke is most of the work.
2. Platform confirmations. The guide is tested on Linux. Runs on macOS or Windows are collected in [issue #6](https://github.com/AlisterBaroi/litellm-kind-deployment/issues/6), and "it just worked" is a result worth reporting.
3. Everything else lives on the [issue tracker](https://github.com/AlisterBaroi/litellm-kind-deployment/issues). Issues labeled `good first issue` are scoped for a first contribution, and each one says how to verify the change.

## How changes land

Fork the repo, make a branch, open a pull request against `main`. Direct pushes to `main` are blocked by a branch ruleset, so the PR path is the same for everyone except the maintainer. Reviews usually happen within a few days.

Every PR runs automated checks:

- Spelling (`typos`): if it flags a word that is actually correct, add an exception in a `_typos.toml` file rather than rewording.
- Links (`lychee`): every URL in the markdown has to resolve. Keep in mind a URL can return 200 and still render something wrong, so look at what you embed, not just its status code.
- A greeting bot welcomes first-time contributors. That comment is automatic, not a review.

A kind-based end-to-end smoke test is planned in [issue #8](https://github.com/AlisterBaroi/litellm-kind-deployment/issues/8) and will join the required checks once it lands.

## Testing your changes

`./scripts/setup.sh` gives you a live gateway on a local kind cluster (set `CLUSTER_NAME` to reuse an existing cluster), and `./scripts/cleanup.sh` removes it. If you change a command in the README, run it exactly as pasted afterwards; the guide's promise is copy-paste correctness, so the pasted form is the one that has to work.

## Style

Write plainly. The README avoids decoration: no exclamation marks, no wall of badges, no filler phrases. New prose should read like the prose around it.

## License

Contributions are accepted under the repo's [MIT license](LICENSE).