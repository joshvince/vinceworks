GATING A RESOURCE THAT ONLY ONE AGENT CAN USE AT A TIME

Written for an agent to follow in a project where more than one session, checkout
or worktree is in use on the same machine. Plain text on purpose: copy it into the
project, adapt the paths, delete it when the work is done.


THE SITUATION THIS IS FOR

Two sessions are working in the same project on the same machine. Something they
both need cannot be used twice at once. The symptom is either a failure, or worse,
a session that appears to be working but is actually waiting on something that will
never free up, or is slow because both are fighting over the same thing.

The classic shape: a tool is started on a fixed port, or a file, directory or socket
has one fixed path, or the application itself refuses to run twice. Nothing enforces
the restriction. Whoever is running has to remember it.


STEP 1: FIND THE SINGLETONS BEFORE WRITING ANYTHING

Do not start with the mechanism. Start by listing what actually collides.

Things worth grepping for:

  - Fixed ports in config files, especially ones matching a tool's default. A tool
    spawned with no explicit port argument takes its default, so a config that says
    "port: 4444" and a spawn that passes no argument are the same fact in two places.
  - Fixed file, socket, lock or directory paths in code, scripts and test setup.
  - Single-instance mechanisms in the application itself. A desktop app with a single
    instance lock will refuse a second launch no matter how the test harness is set
    up, so a port fix alone will not buy concurrency.
  - Shared caches, databases, or anything under a fixed temp path.

The strongest tell is documentation, and it is easy to miss because it reads as
advice rather than as a defect. If a README, an AGENTS.md, a CONTRIBUTING note or a
comment anywhere says some version of "don't run X and Y at the same time", or "close
the app before running the tests", or "avoid overlapping builds", then you have found
an unenforced mutex. That sentence is the bug. Quote it in your notes.

Write the list down with evidence: file and line for each one. If the list is empty,
stop here, there is nothing to do.


STEP 2: CAN THE RESOURCE BE MADE DISTINCT INSTEAD?

For each item on the list, ask whether each session could have its own, rather than
taking turns. A port can usually be allocated per checkout, written into the same
config or .env the rest of that checkout already reads. A temp directory can be
namespaced by checkout. This is strictly better than serialising when it is possible,
because it costs nothing at run time.

Before you conclude it is possible, check for a second singleton hiding behind the
first. The port is often not the only constraint. If the application holds a single
instance lock keyed on its bundle identifier or application name, two concurrent runs
will still collide with distinct ports, and you will have added complexity for no
gain. Only recommend per-checkout resources when you have checked every item on the
list and they can all be made distinct.

If any item genuinely cannot, that session has to take turns. That is not a
compromise, it is the honest answer, and the rest of this guide is for that case.


STEP 3: GATE THE ENTRY POINT, NOT THE AGENT

This is the part that decides whether the fix holds.

The tempting approach is to write an instruction telling agents to wrap their
commands in a lock, or to check whether the resource is free before starting. That
fails, for two reasons. An instruction is only followed if it is remembered at the
right moment, and it competes with every other instruction in the file. And a check
followed by a start is a race: the resource can be taken in between, which is exactly
the situation the check was meant to prevent.

Instead, put the gate inside the project's own entry point for the shared thing, so
that the safe path is the only path. If the suite is started by a task runner script,
a make target, a package script or a shell script, then the gate belongs inside that
script, wrapping the command that actually binds the resource. Then running the suite
is safe by construction, and nobody has to remember anything.

Two consequences worth knowing before you choose this:

  - Nesting has to be handled, because the gated script may itself run something
    that is gated. The mechanism in the appendix marks the environment while it
    holds a slot and passes straight through when the mark is already there.
  - The gate is now in the path of anyone else who runs the script, including a human
    developer or CI. That is usually fine and usually desirable. If it is not, gate a
    separate entry point and document it instead, accepting the weaker guarantee.

Also update any instruction you found in step 1. Rewrite "avoid running X at the same
time" to point at the entry point, or delete the sentence if the entry point now
makes it unnecessary. Leaving the old wording means agents will keep inventing
workarounds for a problem that no longer exists, and those workarounds will be worse
than the thing you just replaced. Keep the replacement short; a long paragraph about
locking will not be read at the moment it matters.

Use a separate gate per resource class. Never put a slow job and a fast job behind
one gate, or the slow one starves the fast one and you have converted a hang into an
outage. A test suite that takes ten minutes and a compile that takes thirty seconds
want different gates even if they contend for the same CPU.


STEP 4: THE MECHANISM

Use the script in the appendix, or write the equivalent. Whatever you write must have
all of these properties, each of which was learned from a real failure:

  - The slot is released when the holder exits, however it exits. Hold a file
    descriptor open on a lock file, or take an flock on one. Do not implement this as
    "create a lock file at the start, delete it at the end": a killed process leaves
    the file behind and the resource is dead forever.
  - It says something the moment it starts waiting. A tool call that produces no
    output looks hung. Both humans and agents respond to that by retrying or killing
    it, which makes the queue worse than the thing they were waiting for.
  - It does not print a queue position unless it can measure one. flock has no queue
    order, so a number you print is fiction. A wrong number is worse than none,
    because somebody will trust it. A heartbeat with elapsed time is honest and
    enough.
  - Waiting is visible, not bounded, by default. A caller that needs a bound should
    wrap the call in timeout. A bound inside the gate turns a legitimate wait into
    a failure, and an agent that sees a failure retries, which lengthens the queue.
  - It fails open when the tooling is missing. If the lock tool is not installed, run
    the command ungated and say so, rather than blocking or failing. A missing
    developer tool should cost you the guarantee, not the build.
  - The path of the lock files is fixed and shared, not derived from the shell or the
    environment. Two callers that disagree about where the locks live will both take
    "the only slot" and the gate will silently stop gating anything.

Check the platform before assuming the tool exists. flock is a util-linux tool and
is absent on macOS by default, so a gate that depends on it will not work there.
Either install it, or use a primitive that exists everywhere: mkdir on a fixed path
is atomic on every platform, and lockf and shlock are the usual macOS answers.
Write the fallback if the project is used on more than one platform, and test both
paths.


STEP 5: PROVE IT WORKS

Before calling this done, demonstrate each of these, and put the evidence in the
commit message or the pull request:

  - Two invocations at once: start one long holder, then run a second and confirm it
    prints that it is waiting, waits, and then runs. Give the timings, not just the
    output.
  - Release on abrupt exit: kill the holder with a signal and confirm the next caller
    runs immediately rather than waiting forever. This is the failure that turns a
    gate into an outage, so it is worth demonstrating rather than reasoning about.
  - Release on normal exit: the caller after a completed run waits zero seconds.
  - Nesting: a gated command that runs another gated command passes through instead of
    deadlocking.
  - Two slots, if the gate allows more than one, run two holders concurrently rather
    than serialising them.
  - The entry point from step 3 is genuinely gated, by running the real thing twice
    at once and observing the wait. Not a synthetic wrapper you wrote for the test.

State plainly what you did not test. If you could not reproduce a concurrent run
because the suite is slow, say so rather than implying you did.


ANTI-PATTERNS, AND WHY

Each of these has caused a real outage. If you find one in the codebase, removing it
is part of this work.

  - A poll loop waiting for something to become free:

        until ! pgrep -f something > /dev/null; do sleep 1; done

    This has no output, no deadline, and no fairness. When it goes wrong it looks
    exactly like a hang, and it produced a 50 minute silent stall in the case this
    guide was written from. If something must be waited for, it belongs behind a gate
    that reports that it is waiting.

  - "Check that the port is free, then start the server." Between the check and the
    bind, another session takes it. Use the kernel's own exclusivity: bind the port,
    or hold a lock, rather than asking politely first.

  - Retry loops around a shared resource. They turn contention into load, and make
    the contention worse for everyone including the thing being waited for.

  - A timeout long enough to look like a hang and short enough to fire during a
    legitimate long run. Either make the operation report progress, or make the
    timeout clearly longer than the operation and say why in a comment.

  - Telling agents to coordinate without giving them a mechanism. Coordination
    instructions are not enforcement, and they decay the moment the file gets long.


APPENDIX: THE SCRIPT

Save as something like bin/with-gate, make it executable, and call it from the
project's entry point. It takes a gate name so that unrelated resources do not share
a queue, and everything after the name is the command to run.

    usage: with-gate <gate> <command> [args...]
           GATE_SLOTS=2 with-gate e2e npm run test:e2e
           GATE_DIR=/var/lock/myproject with-gate e2e npm run test:e2e

Copy from the shebang line below down to the exec line at the end, and nothing else. The
script has to start at the top of its own file: a leading blank line stops the shebang
being read, and the file then gets run by whatever /bin/sh happens to be, which for this
script means failing on set -o pipefail rather than doing anything useful.

-------------------------------------------------------------------------------
#!/usr/bin/env bash
# Runs a command under one of a small number of slots for a named gate, so that
# concurrent sessions take turns over a resource only one of them can use.
#
# Only put things behind a gate that genuinely cannot run at once. If a resource can
# be made per-checkout instead, do that: taking turns costs time every run, and a
# resource that does not collide costs nothing.
set -euo pipefail

gate=${1:?usage: with-gate <gate> <command> [args...]}
shift
[[ $# -ge 1 ]] || { echo "usage: with-gate <gate> <command> [args...]" >&2; exit 2; }

slots=${GATE_SLOTS:-1}
base=${GATE_DIR:-/tmp/with-gate}
dir=$base/$gate

# A gated command can run another gated command, including on the same gate. Pass
# straight through when this process is already holding a slot somewhere in its
# ancestry, or it waits on a lock its own parent is holding and deadlocks.
case ":${GATE_HELD:-}:" in
  *":$gate:"*) exec "$@" ;;
esac

# Fail open if the locking tool is missing: a missing developer tool should cost the
# guarantee, not the command.
if ! command -v flock >/dev/null 2>&1; then
  echo "with-gate: flock unavailable, running the $gate command ungated" >&2
  exec "$@"
fi

mkdir -p "$dir"

# Holding the open descriptor is holding the slot, so it is released when this
# process exits, whatever it exits with, including a signal.
acquire() {
  local i fd
  for (( i = 0; i < slots; i++ )); do
    exec {fd}>>"$dir/slot.$i"
    if flock -n "$fd"; then
      slot=$i
      return 0
    fi
    exec {fd}>&-
  done
  return 1
}

if ! acquire; then
  # Say so immediately. A caller whose tool call produces no output reads as hung,
  # and retries or kills it, which makes the queue worse.
  #
  # No queue position: flock has no queue order, so any number here would be
  # invented, and a number that is wrong is worse than no number.
  waited=0
  printf 'with-gate: all %d slot(s) for %s busy, waiting\n' "$slots" "$gate" >&2
  until acquire; do
    sleep 5
    waited=$(( waited + 5 ))
    (( waited % 30 )) || printf 'with-gate: still waiting for %s, %ds\n' "$gate" "$waited" >&2
  done
  printf 'with-gate: %s slot %d free after %ds\n' "$gate" "$slot" "$waited" >&2
fi

export GATE_HELD="${GATE_HELD:+$GATE_HELD:}$gate"
exec "$@"
-------------------------------------------------------------------------------

That is the end of the script.
