# Making parallel Rust builds viable in the sandbox

The sandbox is built for agents working on one thing at a time. What I actually want is a
handful of ephemeral agents, each on its own worktree, each making a different change to the
same Rust application at the same time. Those two things do not fit together on a four-core
box, and this is the plan for closing the gap.

Nothing here is project-specific on purpose: this repo is public, so the only project detail
that appears is the *shape* of the workload.

## What is in place, and what is still open

Landed: the compile cache, the config file that carries the build settings, the build gate, and
the reaper. The README describes how to use them. The distribution rustc was removed at the
same time, so there is one compiler rather than two that can be mismatched.

Still open, and each of these needs the box rather than a longer argument: timing a cold build
before and after, the incremental question in Phase 2, and the cpuset comparison in Phase 3.
The image has to be rebuilt before the cache exists in the container at all, and rebuilding it
ends every agent session, so it is work to do deliberately rather than fold into something
else.

## The container is one unit, and that sets the stakes

Before any tuning: the container shares a single memory limit and a single volume between
Postgres, the browser engines, the agent daemon, and every build.

That matters because the failure mode is not a slow agent, it is all of them at once. The
container's main process is the agent daemon. If the cgroup OOM killer picks it, the container
exits and the unit's `Restart=always` recreates it, ending every agent session together. Disk
has the same character: the compile cache, the worktree target directories and the database
all live on one volume, and Postgres stops cleanly when that volume fills and nothing restarts
it until the container does.

So memory pressure is a fleet-wide outage risk rather than a per-agent slowdown, and the build
gate below is a memory control first and a CPU control second. The baseline in Phase 0 has to
include OOM kills and free space before anything else changes.

## What the workload looks like

Each ephemeral agent gets its own worktree. Worktrees are cheap in git and expensive in
cargo:

- Every worktree builds its own copy of the dependency tree from cold. Three concurrent
  worktrees of one application meant well over a thousand dependency artifacts compiled,
  where only a few hundred were genuinely distinct.
- The dependency graphs were near-identical across branches (two branches had byte-identical
  lockfiles), so most of that was duplicated work rather than genuinely different work.
- A handful of dependencies are compiled with optimisation on even in dev, which makes them
  the slowest individual compiles in the tree and, being branch-independent, pure duplication.
- Worktree target directories are deleted along with the worktree. Whatever should warm the
  next agent therefore cannot live inside a worktree.
- Tearing down the tree is small; the compile and the link are not. The link phase is
  single-threaded and is a large share of the tail of every build.

## What the box can do

Four cores, no SMT, a three-CPU quota for the container, single-channel memory, and a power
profile already at the chip's maximum. Concretely measured under three concurrent agents:

- Load average of 4-5 on four cores.
- Tens of thousands of cumulative CFS throttle events against the container's quota, and
  around twenty minutes of accumulated throttled time across eleven hours of uptime.
- That throttling happened at roughly 15% average utilisation of the quota. The container was
  not short of CPU on average. It was being punished for being *spiky*, because several
  builds each assumed they owned every core.

That last point is why this plan is mostly about scheduling and cache reuse, and hardly at all
about raising limits.

## Phase 0: measure, and pin the toolchain

Two things have to happen before anything else, because every later phase depends on them.

**Record a baseline**, on a fresh worktree: wall time for a cold build, `cargo build --timings`
to attribute that time between dependencies, the application's own crates, and the link, peak
memory, the container's throttle and pressure counters, **OOM kills**, and **free space on the
volume**. Without the last two, a later phase could look like an improvement while moving the
failure somewhere worse.

**Pin the toolchain, because right now nothing does.** There are two compilers installed: a
distribution-packaged `rustc` that is first on `PATH`, and a rustup toolchain several years
newer that lives in the persistent home and is not on `PATH` at all. Nothing in the repo puts
it there — the rustup environment file exists but no shell or profile file sources it — yet
builds resolve to the newer one. The bridge between those two facts is unmanaged, and finding
it is part of this phase.

It is not cosmetic. A mismatched pair fails outright, with an error that says nothing about
the real cause:

```
$ cargo build            # cargo 1.98, rustc 1.75 from the distribution package
error: the `-Z unstable-options` flag must also be passed to enable the flag `check-cfg`
error: could not compile `...` (build script)
```

So the difference between a working build and this is whether one directory happens to be on
`PATH`. Fix it in the direction that removes the ambiguity rather than adding to it:

- **Remove the distribution `rustc` from the image** rather than putting the rustup one ahead
  of it. There is already a rule here against shadowing anything, and this avoids needing an
  exception to it. Checked before doing it: nothing else in the image depends on the package
  — no installed package lists it as a dependency — so it is a one-line removal. What it costs
  is that a fresh persistent home has no compiler at all, which is why the entrypoint warns at
  startup and the first-boot steps say to install one.
- Note that mise is meant to own language versions, but its shims are appended to `PATH` and
  it has no global config, so a distribution `rustc` would always win over a mise-managed one.
  Removing it also fixes that, before anyone hits it.

Two related facts to write down while here. The application repo pins no toolchain today, so
the sandbox's ambiguity is currently the only thing deciding which compiler is used. If that
repo ever does pin one, the pin wins over anything the sandbox does, because rustup proxies
honour it regardless of `PATH` — which means branches pinning different versions will split
the compile cache. That is a decision for the application repo, not something the sandbox can
paper over.

## Phase 1: make each build cheaper

Full debug information for the whole dependency tree costs a lot of compile time and most of
the disk each worktree occupies, and almost none of it is ever read: agents debug their own
code, not the internals of a dependency.

**This phase needs no change to the application repo.** A profile override in the cargo
configuration file is enough, so the sandbox carries it and the application stays untouched.
Verified on the installed cargo against a scratch crate: with the override in place the
dependency's artifact has no debug sections at all while the workspace's own binary still has
them, and the override applies only to dependencies, never to the application's own crates.
That is exactly the split wanted, and it means the effect is visible per artifact rather than
being taken on faith.

`line-tables-only` for dependencies is the middle ground if a dependency stack frame ever
matters.

The other half of this phase is the cheap inner loop. For resolving compile errors,
`cargo check` skips code generation and linking entirely and is dramatically cheaper than a
full build. Agents should check while they iterate and build only when they need to run
something. That is guidance for per-project agent instructions; the sandbox cannot enforce it.

Re-measure after both.

## Phase 2: a compile cache that outlives the worktree

`sccache` is the right mechanism here, and it is worth writing down why, because the obvious
alternative looks like it does the same job and does not.

It fits because its cache is content-addressed, immutable, and unlocked:

- It lives in the persistent home, so it survives worktree teardown, container restarts, and
  image rebuilds. Nothing inside a worktree can, by definition.
- An agent deleting its own worktree, or its target directory, damages nobody else.
- It takes no global lock, so agents stay genuinely parallel.
- One cache serves every Rust project on the box, not one cache per project.

### Wire it through a cargo config file, not the environment

This is the part it would be easy to get wrong. The plan originally proposed setting
environment variables on the container. That does not work here: sshd starts sessions with a
clean environment, which is why the entrypoint already re-exports a list of variables into
`.zshenv` by hand. Adding another variable to that list would put the configuration back into
a shell rc file that is rewritten on every container start and is only read by zsh — the exact
dependency worth avoiding, since an agent's build may never go through that file.

Instead, use a cargo configuration file, copied into place by the entrypoint alongside the
other dotfiles it already manages. Every cargo reads it regardless of shell, environment, or
how the agent reached the compiler. It carries:

- the wrapper path
- `build.jobs`, set explicitly. Cargo's detection of a cgroup quota depends on the toolchain
  version and on cgroup v1 versus v2, so relying on it is a coin flip; with three CPUs
  available, three jobs is the number.
- the dependency debug profile from Phase 1
- the cache location and size, under an `[env]` section — verified to reach the wrapper
  process, which is what needs them

### Fail open, not closed

A wrapper path is a hard dependency for *every* cargo command in the container, so a cache
binary that is missing — a fresh persistent home, or one that predates the install — would
break every build rather than simply falling back to compiling. That is not a guess: with the
wrapper set and the binary absent, cargo fails like this, and the error never mentions the
cache.

```
error: could not execute process `/usr/local/bin/sccache ... -vV` (never executed)
```

So the binary is baked into the image, the way the agent tooling already keeps a fallback copy,
and the entrypoint uncomments the wrapper setting only when the binary is really there.

### Check the incremental claim before acting on it

An earlier draft of this plan asserted that disabling incremental compilation was mandatory,
on the grounds that sccache cannot cache incremental artifacts and errors on them. The first
half is right; the second half is unverified for the version we would install. And it matters
that it is right, because cargo only compiles workspace members incrementally by default, so
dependencies are already non-incremental and already cacheable without the setting. If sccache
passes incremental crates through uncached rather than failing, then forcing it off globally
buys nothing for the cache and slows the application's own edit-and-rebuild loop. Test it on
the installed version and only then decide.

### Accept and do not try to fix

- Anything that invokes the system linker cannot be cached: binaries, dynamic libraries, and
  procedural macros. An application that produces a library plus a desktop binary is made of
  exactly those, so its own crate and its link are never cacheable.
- The linker is single-threaded and stays per-worktree.
- There is no in-flight de-duplication. Several agents starting a cold build at the same
  moment still compile more than once. That is Phase 3's problem.
- Cargo also takes a lock on the shared registry and package cache. It is brief, but it
  serialises concurrent cargo starts across all worktrees and will show up in timings as
  "Blocking waiting for file lock". Not a problem to solve, just not to be surprised by.

Validate with `sccache --show-stats` across two cold worktrees and read the hit rate, not the
cache size.

## Phase 3: a build gate

This is the part that addresses what was actually measured, and the part where the details
decide whether it helps or makes things worse.

The principle to design around: **on this box, one build at a time using every core beats
several builds sharing cores.** It is not a scheduling technicality. Memory is single-channel,
so concurrent rustc processes compete for bandwidth. Peak compile and link memory multiplies
inside a container memory limit that is shared with the database and the browsers, which is
the outage risk from the top of this document. And each build spends its tail in a
single-threaded link that gets starved when other builds are competing. Several builds each
running four jobs is the worst configuration available, and it is the current one.

Requirements for the gate, in rough order of how much trouble they save:

- **Say something immediately, and say where you are in the queue.** An agent waiting behind
  two builds does not look idle. Its shell tool has a short default timeout, so it sees a
  failed command, retries, and makes the queue worse. The gate has to print a waiting message
  and a queue position straight away, and the per-project agent instructions should tell
  agents to run gated builds in the background or with the maximum timeout. Note that plain
  `flock` cannot report a queue position, so this requirement decides the mechanism: either a
  ticket or turnstile arrangement, or waiters that record themselves so their position can be
  counted.
- **Never hold a slot for a long-running process.** A gated `cargo run` that starts a dev
  server would hold its slot until the server exits, blocking everyone. The gate should cover
  build, check and test, and let everything else through untouched.
- **Do not deadlock on nesting.** A test that shells out to another gated build would wait on
  a lock its own parent already holds. Mark the environment when a slot is held and pass
  straight through when the marker is already set.
- Release the slot as soon as the compile or test finishes, and expose the gate somewhere
  discoverable rather than leaving it as folklore — the existing scripts in this directory
  have a `vinceworks sandbox` subcommand pattern to follow.

Trade-off to accept deliberately: queued agents block, and will look idle. That is the right
call when the goal is throughput across many anonymous tasks, and the wrong call for a single
latency-sensitive one. If a specific task needs to be fast, it can be given its own slot.

Also worth measuring here rather than assuming: the quota is what produces the throttle
counters, and pinning the container to specific cores instead of giving it a quota would
remove the mechanism entirely, so bursts time-share rather than being punished for it. It is a
one-line change to the unit and it belongs in the Phase 0 comparison.

## Phase 4: housekeeping

Worktrees are cheap in git and expensive in cargo, and dead ones each hold several gigabytes.
Most session directories were already empty shells, so some cleanup is happening; make it
unconditional, and check whether the agent platform has a scheduled-cleanup hook before
writing one.

The two kinds of leftover are not equally safe to delete:

- **Target directories** can be reaped by age. They are reproducible, and deleting one costs a
  rebuild and nothing else.
- **Worktrees** may hold commits an agent never pushed, and an agent that died mid-task leaves
  no other trace of that work. Only reap a worktree when its branch is pushed or merged, and
  never while an agent is live. Age alone is not sufficient evidence.

Two things worth knowing before trusting any of this. There is **more than one layout**: Paseo
puts a worktree directly under a session directory, and the agent harness nests its own deeper,
`<session>/worktrees/<agent>/pi-worktree-<uuid>/`. That depth has changed once already, so
discover worktrees by asking git (`git worktree list`) rather than by walking a fixed number of
levels — anything that assumes two finds a third of them and reports the rest as nothing to do.

And a checkout under `~/projects` can be a linked worktree rather than a main checkout, so
"not the main checkout" is not a safe test on its own. That directory is the operator's, so
reaping is scoped to the agents' worktree area, and anything under `~/projects` is reported but
never deleted. Build output inside it is still fair game, because a rebuild restores it.

## Phase 5: re-measure, then decide about hardware

Same measurements as Phase 0, including the OOM and free-space numbers. If parallel changes to
the same application are still the steady state after Phases 1 to 4, the remaining constraint
is silicon: a low-power four-core with single-channel memory, already running at its maximum
power profile. More quota is not the answer; more cores *plus* dual-channel memory is.

Separately and with its own measurement: the toolchain is well behind current stable, and the
two installed compilers show how far apart that can drift. Newer compilers are generally
faster, but this is a change to the thing everything else depends on, so it does not belong
bundled into this work.

## What does not work, so nobody spends a weekend on it

**A shared `CARGO_TARGET_DIR`.** It looks like the obvious fix and it is the wrong shape. Cargo
locks the target directory for the duration of a build, so parallel agents become a queue.
Worse for disposable agents, it makes the build cache a shared failure domain: one agent that
runs `cargo clean` after a confusing build error destroys everyone else's warm cache. It also
cannot serve more than one project.

**Copy-on-write clones of a prebuilt target directory.** This would be the ideal answer for
disposable worktrees: near-free, instant, and full cargo semantics with none of the cache's
caveats. The volume is ext4, which has no reflink support, so a "copy" is a real copy and costs
more than rebuilding. Worth revisiting only if the box is ever rebuilt on btrfs or XFS.

**Pre-warming each worktree in the checkout hook.** It serialises at worktree creation, and it
contradicts the rule that hooks do plumbing and nothing else.

## Measurements worth keeping

Recorded before and after each phase, so the effect of a change is never assumed:

- Cold build wall time on a fresh worktree.
- `cargo build --timings`, for the split between dependencies, the application's crates, and
  the link.
- `sccache --show-stats`, for hit rate rather than cache size.
- The container's `cpu.stat` throttle counters and `cpu.pressure`, sampled over a build.
- `memory.events`, especially `oom_kill`, and peak memory — to see whether concurrent builds
  are what drives the container towards the ceiling that would take the daemon with it.
- Free space on the volume, not just the size of the target directories.
- Disk occupied by worktree target directories.
