# TODO

Ideas for later versions of the remote dev environments in `projects/`. Not committed to, just parked.

- **Paseo on the box.** Run the Paseo daemon on `vince-archive` pointed at `/home/josh/projects/<name>`. The paths match inside the containers, so it may work with little glue.
- **pi as the coding harness.** Replace Claude Code inside the container with pi.
- **opencode go as the model provider for pi.**
- **speak-like-you-eat or nopus with pi.**
- **Podman instead of Docker for the dev containers.** Rootless, so a stray agent cannot reach host root, and it drops the root-equivalent `docker` group. Blocked: the box is Ubuntu 22.04, whose only podman is 3.4.4 from 2021. Revisit after upgrading the box to 24.04. Full plan in `projects/docs/podman-migration.md`.
- **Tailscale.** The box is only reachable on the home LAN today. Install Tailscale on the box and the Mac so `projects` works from anywhere, and point the `vince-archive` SSH alias at the Tailscale name.
