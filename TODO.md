# TODO

Ideas for later versions of the remote dev environments in `projects/`. Not committed to, just parked.

- **Paseo on the box.** Run the Paseo daemon on `vince-archive` pointed at `/home/josh/projects/<name>`. The paths match inside the containers, so it may work with little glue.
- **pi as the coding harness.** Replace Claude Code inside the container with pi.
- **opencode go as the model provider for pi.**
- **speak-like-you-eat or nopus with pi.**
- **Tailscale.** The box is only reachable on the home LAN today. Install Tailscale on the box and the Mac so `projects` works from anywhere, and point the `vince-archive` SSH alias at the Tailscale name.
- **Zed remote dev.** Zed's remote-SSH needs a real `ssh` target, but containers have no sshd (kept that way so the coding agent inside never has access to a private key or another listening service — see README). Recommended: a `~/.ssh/config` `Host` entry per project using `ProxyCommand` to shell through `ssh vince-archive -- docker exec -i project-<name> ...`, so Zed thinks it's SSHing but actually lands inside the container via `docker exec`. No sshd added, no key enters the container, and Zed sees the same `mise` toolchain the container's LSPs use (a straight SSH to the host itself wouldn't, since the toolchain lives in a Docker volume).
