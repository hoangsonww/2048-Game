# Releasing

Releases used to be made by hand: tag whatever `main` happened to be, write the
notes, and stop. Nothing was attached, so there was nothing to download — the
Android app could only be had by installing a JDK and the Android SDK and
building it yourself, and the iOS app not at all.

There is now one button. It moves the version, tags, builds all three clients,
attaches their artifacts, and refuses to report success unless a release with
those files actually exists.

## Cutting a release

Actions → **Cut release** → Run workflow. Choose `patch`, `minor`, or `major`.
Leave `dry_run` off to publish; turn it on to see what would happen without
tagging or pushing anything.

That is the whole procedure. Do not tag by hand.

## The version

`VERSION` at the repository root is the only place a human edits the version.
Everything else is derived from it by `scripts/version.sh`:

| Where | What it sets |
| --- | --- |
| `package.json` | `version` |
| `Android-Version/Game2048/app/build.gradle.kts` | `versionName`, `versionCode` |
| `2048 Game.xcodeproj/project.pbxproj` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, in every build configuration |

`versionCode` is derived rather than tracked separately: `MAJOR * 10000 +
MINOR * 100 + PATCH`, so 2.1.3 becomes 20103. It stays monotonic as long as
minor and patch remain below 100, and there is no second number to forget.

```bash
make version        # print the version and check every client agrees
make version-sync   # rewrite the derived files from VERSION
scripts/version.sh set 2.1.0
scripts/version.sh bump minor
```

The check is not advisory. It runs in `make check`, in CI on every push and
pull request, and again at the tag before any artifact is built. These files
had drifted four ways at once — `package.json` said 1.2.0, Android said 1.0
with a `versionCode` of 1, Xcode said 1.0, and the newest release was v2.0.0 —
which is the failure the gate exists to prevent recurring.

## What each release contains

| Artifact | Built by | Notes |
| --- | --- | --- |
| `2048-vX.Y.Z-debug.apk` | `android-apk` | Installable on any device with unknown sources enabled |
| `2048-vX.Y.Z-ios-unsigned.zip` | `ios-app` | Unsigned `.app` for the simulator, or to sign yourself |
| `2048-vX.Y.Z-web.zip` | `web-bundle` | The shipping web client — unzip and serve the folder |
| `SHA256SUMS-ios.txt`, `SHA256SUMS-web.txt` | those jobs | Checksums for the two zips |

The iOS artifact is deliberately unsigned. Signing needs a provisioning profile
and a team identifier, neither of which belongs in a public repository, so App
Store distribution stays a manual step outside this pipeline.

## How it fits together

```
Cut release (workflow_dispatch)
  ├─ version.sh check          the tree must agree with itself first
  ├─ bump VERSION, propagate, open the changelog section
  ├─ commit + tag vX.Y.Z + push
  ├─ dispatch Release at the tag
  └─ wait, then confirm a release exists with its artifacts attached
        │
        └─ Release
             ├─ prepare       resolve the tag, check it matches VERSION, create the release
             ├─ android-apk   ─┐
             ├─ ios-app        ├─ build, then upload into the existing release
             ├─ web-bundle    ─┘
             └─ verify        every expected file is attached, or the run fails
```

Three details in there are not decoration:

**A tag pushed by a workflow starts nothing.** GitHub suppresses workflow
triggers for events raised by `GITHUB_TOKEN`, to stop workflows retriggering
themselves. So `Cut release` cannot push the tag and walk away — it dispatches
`Release` by name, at that tag. Dispatching also needs `actions: write`;
`actions: read` gets a 403.

**One job creates the release, three upload into it.** Letting each build job
create-if-missing reads as harmless and is a race: all three start together,
all three see no release, and two fail with "already exists". That is an
intermittent red cross that says nothing about the code.

**A green build is not a release.** The `verify` job looks at what is attached
to the release, not at whether the jobs reported success — and `Cut release`
checks again afterwards. An earlier version of this pipeline in a sibling
repository reported success having published nothing at all, which is worse
than failing, because nobody goes looking.

## When something fails

The pipeline is designed so that a failure leaves a diagnosable state rather
than a half-published release.

- **`version.sh check` fails at the start** — the tree disagrees with itself.
  Run `make version-sync`, commit, and cut again. Nothing was pushed.
- **The tag already exists** — `Cut release` refuses rather than moving it.
  Bump past it.
- **A build job fails** — the release exists with fewer artifacts, and `verify`
  fails naming the missing file. Fix the build, then re-run `Release` via
  `workflow_dispatch` with that tag; uploads use `--clobber`, so re-running is
  safe and idempotent.
- **`Cut release` times out waiting** — it waits 40 minutes. The tag and commit
  are already pushed; check the `Release` run and re-dispatch it if needed.
- **The dispatch cannot find the tag** — retried six times over a minute, since
  the tag was pushed seconds earlier and the API resolving `--ref` can lag its
  own push. If all six fail the job says so and names the tag to re-dispatch by
  hand; the bump itself is already committed, so do not cut again.

Re-running `Release` at an existing tag is always safe. It rebuilds from the
tag, so it produces the same artifacts, and replaces rather than duplicates
them.
