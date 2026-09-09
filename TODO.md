# TODO

Ideas for later versions of the remote dev environments in `projects/`. Not committed to, just parked.

- **Paseo on the box.** Run the Paseo daemon on `vince-archive` pointed at `/home/josh/projects/<name>`. The paths match inside the containers, so it may work with little glue.
- **pi as the coding harness.** Replace Claude Code inside the container with pi.
- **opencode go as the model provider for pi.**
- **speak-like-you-eat or nopus with pi.**
- **Podman instead of Docker for the dev containers.** Rootless, so a stray agent cannot reach host root, and it drops the root-equivalent `docker` group. Unblocked on 2026-09-09: the box is now Ubuntu 24.04.5, which carries podman 4.9.3. The repo side is done — `projects-host` defaults to podman and `PROJECTS_ENGINE=docker` rolls it back. What is left is installing podman on the box and working through the cutover checklist. Full plan in `projects/docs/podman-migration.md`.
- **A real hostname for the dev environments.** Reaching a project means typing a LAN IP and a port. `vince-archive` is only an SSH config alias, so it does not resolve in a browser or in `curl`, which also makes `vinceworks projects open` fail. Something memorable and resolvable, per project or per port, would be better than remembering which number belongs to which repo.

- **Tailscale.** The box is only reachable on the home LAN today. Install Tailscale on the box and the Mac so `projects` works from anywhere, and point the `vince-archive` SSH alias at the Tailscale name.
- **Zed remote dev.** Zed's remote-SSH needs a real `ssh` target, but containers have no sshd (kept that way so the coding agent inside never has access to a private key or another listening service — see README). Recommended: a `~/.ssh/config` `Host` entry per project using `ProxyCommand` to shell through `ssh vince-archive -- docker exec -i project-<name> ...`, so Zed thinks it's SSHing but actually lands inside the container via `docker exec`. No sshd added, no key enters the container, and Zed sees the same `mise` toolchain the container's LSPs use (a straight SSH to the host itself wouldn't, since the toolchain lives in a Docker volume).
